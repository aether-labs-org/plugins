// Package memory checks the versioned memory of a repository: active plans,
// the task history and triaged lessons. kh only reads and checks them; the
// agent writes them (the human confirms what is shared).
package memory

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/aether-labs-org/plugins/cli/kh/internal/redact"
)

// Issue is one problem in a memory file.
type Issue struct {
	File string
	Line int
	Msg  string
}

// Plan is an active plan.
type Plan struct {
	Path, Title, Status string
	Scope               []string
	Acceptance          int
}

const (
	plansDir     = ".agents/plans"
	progressFile = ".agents/progress.md"
	lessonsFile  = ".agents/lessons.md"
)

func lines(content string) []string {
	return strings.Split(strings.ReplaceAll(content, "\r\n", "\n"), "\n")
}

var (
	titleRE      = regexp.MustCompile(`^# +\S`)
	statusRE     = regexp.MustCompile(`^Status: *(.*?) *$`)
	scopeRE      = regexp.MustCompile(`^Scope: *(.*?) *$`)
	acceptRE     = regexp.MustCompile(`^## +Acceptance *$`)
	checkItemRE  = regexp.MustCompile(`^- \[[ xX]\] +\S`)
	headingRE    = regexp.MustCompile(`^#{1,6} `)
	progressRE   = regexp.MustCompile(`^- \d{4}-\d{2}-\d{2} [a-z0-9][a-z0-9-]*: (done|partial|abandoned) — .+$`)
	lessonHeadRE = regexp.MustCompile(`^## \d{4}-\d{2}-\d{2} +\S`)
	destRE       = regexp.MustCompile(`^(rule [a-z0-9-]+|ADR \d{4}|guide \S+|none)$`)
)

// parsePlan reads one plan file.
func parsePlan(rel, content string) (Plan, []Issue) {
	p := Plan{Path: rel}
	var is []Issue
	add := func(line int, msg string) { is = append(is, Issue{rel, line, msg}) }
	ls := lines(content)
	if len(ls) == 0 || !titleRE.MatchString(ls[0]) {
		add(1, "line 1 must be the title: # <title>")
	} else {
		p.Title = strings.TrimSpace(strings.TrimLeft(ls[0], "# "))
	}
	statusLn, scopeLn, accLn := 0, 0, 0
	for i, l := range ls {
		n := i + 1
		switch {
		case statusRE.MatchString(l) && statusLn == 0:
			statusLn = n
			p.Status = statusRE.FindStringSubmatch(l)[1]
		case scopeRE.MatchString(l) && scopeLn == 0:
			scopeLn = n
			for _, g := range strings.Split(scopeRE.FindStringSubmatch(l)[1], ",") {
				if g = strings.TrimSpace(g); g != "" {
					p.Scope = append(p.Scope, g)
				}
			}
		case acceptRE.MatchString(l) && accLn == 0:
			accLn = n
			for _, a := range ls[i+1:] {
				if headingRE.MatchString(a) {
					break
				}
				if checkItemRE.MatchString(a) {
					p.Acceptance++
				}
			}
		}
	}
	if statusLn == 0 {
		add(1, "missing a line: Status: active")
	} else if p.Status != "active" {
		add(statusLn, "Status must be active; delete the plan when the task is closed")
	}
	if scopeLn == 0 {
		add(1, "missing a line: Scope: <glob>[, <glob>...]")
	} else if len(p.Scope) == 0 {
		add(scopeLn, "Scope must list at least one glob")
	}
	if accLn == 0 {
		add(1, "missing the heading: ## Acceptance")
	} else if p.Acceptance == 0 {
		add(accLn, "## Acceptance needs at least one checklist item (- [ ] ...)")
	}
	return p, is
}

// ActivePlans reads .agents/plans/*.md. Plans that parse and are active are
// returned; every problem of every plan is an issue. No plans directory is not
// an error.
func ActivePlans(root string) ([]Plan, []Issue, error) {
	files, err := filepath.Glob(filepath.Join(root, filepath.FromSlash(plansDir), "*.md"))
	if err != nil {
		return nil, nil, err
	}
	sort.Strings(files)
	var plans []Plan
	var issues []Issue
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			return plans, issues, err
		}
		rel := plansDir + "/" + filepath.Base(f)
		p, is := parsePlan(rel, string(b))
		issues = append(issues, is...)
		issues = append(issues, Forbidden(rel, string(b))...)
		if len(is) == 0 {
			plans = append(plans, p)
		}
	}
	return plans, issues, nil
}

func readOptional(root, rel string) (string, bool) {
	b, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(rel)))
	if err != nil {
		return "", false
	}
	return string(b), true
}

// CheckProgress checks .agents/progress.md: one line per closed task.
func CheckProgress(root string) []Issue {
	content, ok := readOptional(root, progressFile)
	if !ok {
		return nil
	}
	var is []Issue
	for i, l := range lines(content) {
		if strings.TrimSpace(l) == "" || strings.TrimSpace(l) == "# Progress" {
			continue
		}
		if !progressRE.MatchString(l) {
			is = append(is, Issue{progressFile, i + 1, "expected: - YYYY-MM-DD <slug>: done|partial|abandoned — <one line>"})
		}
	}
	return append(is, Forbidden(progressFile, content)...)
}

// CheckLessons checks .agents/lessons.md: entries of Problem, Solution and
// Destination.
func CheckLessons(root string) []Issue {
	content, ok := readOptional(root, lessonsFile)
	if !ok {
		return nil
	}
	var is []Issue
	ls := lines(content)
	type entry struct {
		line              int
		problem, solution bool
		dest              string
		destLine          int
		hasDest           bool
	}
	var cur *entry
	flush := func() {
		if cur == nil {
			return
		}
		if !cur.problem {
			is = append(is, Issue{lessonsFile, cur.line, "entry lacks a line: Problem: ..."})
		}
		if !cur.solution {
			is = append(is, Issue{lessonsFile, cur.line, "entry lacks a line: Solution: ..."})
		}
		switch {
		case !cur.hasDest:
			is = append(is, Issue{lessonsFile, cur.line, "entry lacks a line: Destination: rule <id> | ADR NNNN | guide <path> | none"})
		case !destRE.MatchString(cur.dest):
			is = append(is, Issue{lessonsFile, cur.destLine, "Destination must be: rule <id> | ADR NNNN | guide <path> | none"})
		}
	}
	for i, l := range ls {
		n := i + 1
		switch {
		case lessonHeadRE.MatchString(l):
			flush()
			cur = &entry{line: n}
		case strings.HasPrefix(l, "## "):
			flush()
			cur = nil
			is = append(is, Issue{lessonsFile, n, "entry heading must be: ## YYYY-MM-DD <title>"})
		case cur != nil && strings.HasPrefix(l, "Problem: ") && strings.TrimSpace(l[9:]) != "":
			cur.problem = true
		case cur != nil && strings.HasPrefix(l, "Solution: ") && strings.TrimSpace(l[10:]) != "":
			cur.solution = true
		case cur != nil && strings.HasPrefix(l, "Destination: "):
			cur.hasDest, cur.dest, cur.destLine = true, strings.TrimSpace(l[13:]), n
		}
	}
	flush()
	return append(is, Forbidden(lessonsFile, content)...)
}

var (
	homePath  = regexp.MustCompile(`/home/[^/\s]+/`)
	usersPath = regexp.MustCompile(`/Users/[^/\s]+/`)
	runDir    = regexp.MustCompile(`\.agents/run/`)
	runID     = regexp.MustCompile(`\b\d{8}-\d{6}-[0-9a-f]{4}\b`)
)

// Forbidden reports what must never be committed in a memory file: absolute
// user paths, references to the local evidence (.agents/run/ or a run id) and
// secret-looking text.
func Forbidden(path, content string) []Issue {
	var is []Issue
	for i, l := range lines(content) {
		for _, c := range []struct {
			re  *regexp.Regexp
			msg string
		}{
			{homePath, "absolute user path (/home/<user>): memory is shared, use repository-relative paths"},
			{usersPath, "absolute user path (/Users/<user>): memory is shared, use repository-relative paths"},
			{runDir, "reference to .agents/run/ (local evidence): it is not shared"},
			{runID, "run id (local evidence): it is not shared"},
		} {
			if c.re.MatchString(l) {
				is = append(is, Issue{path, i + 1, c.msg})
			}
		}
		if redact.Contains(l) {
			is = append(is, Issue{path, i + 1, "secret-looking text"})
		}
	}
	return is
}

// All checks every memory file and returns the issues in a stable order. It
// also reports how many files exist.
func All(root string) (files int, issues []Issue, err error) {
	plans, err := filepath.Glob(filepath.Join(root, filepath.FromSlash(plansDir), "*.md"))
	if err != nil {
		return 0, nil, err
	}
	files = len(plans)
	for _, f := range []string{progressFile, lessonsFile} {
		if _, ok := readOptional(root, f); ok {
			files++
		}
	}
	_, is, err := ActivePlans(root)
	if err != nil {
		return files, nil, err
	}
	issues = append(issues, is...)
	issues = append(issues, CheckProgress(root)...)
	issues = append(issues, CheckLessons(root)...)
	sort.SliceStable(issues, func(i, j int) bool {
		if issues[i].File != issues[j].File {
			return issues[i].File < issues[j].File
		}
		return issues[i].Line < issues[j].Line
	})
	return files, issues, nil
}
