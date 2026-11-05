package builtin

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/memory"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/result"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/scope"
)

func init() {
	register(scopeBuiltin{})
	register(mergeCheck{})
	register(commitMessage{})
	register(branchName{})
}

// -------------------------------------------------------------------- scope

type scopeBuiltin struct{}

type noParams struct{}

func (scopeBuiltin) Name() string         { return "scope" }
func (scopeBuiltin) DefaultClass() string { return "heuristic" }

func (scopeBuiltin) Decode(with map[string]any) (any, []string) { return decodeWith[noParams](with) }

// planFiles are the memory files a plan may leave out of its Scope.
func isPlanFile(f string) bool {
	return strings.HasPrefix(f, ".agents/plans/") || f == ".agents/progress.md" || f == ".agents/lessons.md"
}

func (scopeBuiltin) Run(ctx Context, _ any) Outcome {
	plans, _, err := memory.ActivePlans(ctx.Root)
	if err != nil {
		return Outcome{Status: result.Error, Summary: err.Error()}
	}
	if len(plans) == 0 {
		return Outcome{Status: result.Skip, Summary: "no active plan"}
	}
	var fs []result.Finding
	checked := 0
	for _, f := range ctx.Files {
		if isPlanFile(f) {
			continue
		}
		checked++
		in := false
		for _, p := range plans {
			for _, g := range p.Scope {
				if scope.MatchOne(g, f) {
					in = true
				}
			}
		}
		if !in {
			fs = append(fs, result.Finding{File: f, Rule: "scope", Severity: "warning", Message: "outside the Scope of every active plan"})
		}
	}
	g := "add the path to the plan's Scope or revert the change"
	if checked == 0 {
		return Outcome{Status: result.Skip, Summary: "no changed files in scope"}
	}
	if len(fs) == 0 {
		return Outcome{Status: result.Pass, Summary: fmt.Sprintf("%d changed file(s), all inside the Scope of an active plan", checked), Guidance: g}
	}
	return Outcome{Status: result.Fail, Summary: fmt.Sprintf("%d of %d changed file(s) outside the plan Scope", len(fs), checked), Findings: fs, Guidance: g}
}

// -------------------------------------------------------------- merge-check

type mergeCheck struct{}

func (mergeCheck) Name() string { return "merge-check" }

func (mergeCheck) Decode(with map[string]any) (any, []string) { return decodeWith[noParams](with) }

var gitVersionRE = regexp.MustCompile(`git version (\d+)\.(\d+)`)

func gitAtLeast(root string, major, minor int) bool {
	out, err := scope.Git(root, "--version")
	if err != nil {
		return false
	}
	m := gitVersionRE.FindStringSubmatch(string(out))
	if m == nil {
		return false
	}
	var a, b int
	fmt.Sscanf(m[1], "%d", &a)
	fmt.Sscanf(m[2], "%d", &b)
	return a > major || (a == major && b >= minor)
}

func (mergeCheck) Run(ctx Context, _ any) Outcome {
	if !gitAtLeast(ctx.Root, 2, 38) {
		return Outcome{Status: result.Skip, Summary: "git 2.38+ needed"}
	}
	if _, err := scope.Git(ctx.Root, "rev-parse", "-q", "--verify", "HEAD^{commit}"); err != nil {
		return Outcome{Status: result.Skip, Summary: "no commits yet"}
	}
	up := ""
	if out, err := scope.Git(ctx.Root, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"); err == nil {
		up = strings.TrimSpace(string(out))
	}
	if up == "" {
		if out, err := scope.Git(ctx.Root, "rev-parse", "--abbrev-ref", "origin/HEAD"); err == nil {
			up = strings.TrimSpace(string(out))
		}
	}
	if up == "" {
		return Outcome{Status: result.Skip, Summary: "no upstream"}
	}
	behind := 0
	if out, err := scope.Git(ctx.Root, "rev-list", "--count", "HEAD.."+up); err == nil {
		fmt.Sscanf(strings.TrimSpace(string(out)), "%d", &behind)
	}
	out, err := scope.Git(ctx.Root, "merge-tree", "--write-tree", "--name-only", "HEAD", up)
	if err == nil {
		return Outcome{Status: result.Pass, Summary: fmt.Sprintf("no conflicts, %d commits behind %s", behind, up)}
	}
	// exit 1 with output: conflicts; anything else is an error
	if !strings.Contains(err.Error(), "exit status 1") {
		return Outcome{Status: result.Error, Summary: "git merge-tree: " + err.Error()}
	}
	_ = out
	return conflictOutcome(ctx.Root, up, behind)
}

// conflictOutcome lists the conflicted files (merge-tree prints them after the
// tree id; Git() drops stdout on failure, so run it again keeping it).
func conflictOutcome(root, up string, behind int) Outcome {
	files := conflicted(root, up)
	var fs []result.Finding
	for _, f := range files {
		fs = append(fs, result.Finding{File: f, Rule: "merge-check", Severity: "error", Message: "conflicts with " + up})
	}
	return Outcome{Status: result.Fail, Summary: fmt.Sprintf("%d conflicting file(s), %d commits behind %s", len(files), behind, up), Findings: fs,
		Guidance: "merge or rebase " + up + " into your branch and resolve the conflicts above before pushing"}
}

func conflicted(root, up string) []string {
	out := scope.GitAllowFail(root, "merge-tree", "--write-tree", "--name-only", "HEAD", up)
	var files []string
	lines := strings.Split(string(out), "\n")
	for i, l := range lines {
		if i == 0 {
			continue // the tree id
		}
		if l == "" {
			break // then the informational messages
		}
		files = append(files, l)
	}
	return files
}

// ----------------------------------------------------------- commit-message

type commitMessage struct{}

type patternOnly struct {
	Pattern string `json:"pattern"`
}

func (commitMessage) Name() string { return "commit-message" }

func decodePattern(with map[string]any) (any, []string) {
	p, problems := decodeWith[patternOnly](with)
	if len(problems) > 0 {
		return p, problems
	}
	if p.Pattern == "" {
		return p, []string{"pattern is required"}
	}
	if _, err := regexp.Compile(p.Pattern); err != nil {
		return p, []string{"pattern is not a valid regular expression: " + err.Error()}
	}
	return p, nil
}

func (commitMessage) Decode(with map[string]any) (any, []string) { return decodePattern(with) }

// CheckMessage matches the first non-comment, non-empty line of a commit
// message against a Go regular expression and returns that line.
func CheckMessage(msg, pattern string) (ok bool, firstLine string) {
	for _, l := range strings.Split(strings.ReplaceAll(msg, "\r\n", "\n"), "\n") {
		if strings.HasPrefix(l, "#") || strings.TrimSpace(l) == "" {
			continue
		}
		firstLine = strings.TrimRight(l, " \t")
		break
	}
	re, err := regexp.Compile(pattern)
	if err != nil {
		return false, firstLine
	}
	return re.MatchString(firstLine), firstLine
}

func (commitMessage) Run(ctx Context, params any) Outcome {
	if ctx.CommitMsgFile == "" {
		return Outcome{Status: result.Skip, Summary: "runs from the commit-msg hook"}
	}
	p := params.(patternOnly)
	b, err := os.ReadFile(filepath.Clean(ctx.CommitMsgFile))
	if err != nil {
		return Outcome{Status: result.Error, Summary: "cannot read the commit message: " + err.Error()}
	}
	ok, first := CheckMessage(string(b), p.Pattern)
	g := "write the first line of the message to match " + p.Pattern
	if ok {
		return Outcome{Status: result.Pass, Summary: "the commit message matches", Guidance: g}
	}
	return Outcome{Status: result.Fail, Summary: "the commit message does not match " + p.Pattern,
		Findings: []result.Finding{{Rule: "commit-message", Severity: "error", Message: first}}, Guidance: g}
}

// -------------------------------------------------------------- branch-name

type branchName struct{}

func (branchName) Name() string         { return "branch-name" }
func (branchName) DefaultClass() string { return "heuristic" }

func (branchName) Decode(with map[string]any) (any, []string) { return decodePattern(with) }

func (branchName) Run(ctx Context, params any) Outcome {
	p := params.(patternOnly)
	out, err := scope.Git(ctx.Root, "branch", "--show-current")
	if err != nil {
		return Outcome{Status: result.Error, Summary: err.Error()}
	}
	name := strings.TrimSpace(string(out))
	if name == "" {
		return Outcome{Status: result.Skip, Summary: "detached HEAD"}
	}
	g := "rename the branch (git branch -m) to match " + p.Pattern
	if regexp.MustCompile(p.Pattern).MatchString(name) {
		return Outcome{Status: result.Pass, Summary: "branch " + name + " matches", Guidance: g}
	}
	return Outcome{Status: result.Fail, Summary: "branch " + name + " does not match " + p.Pattern,
		Findings: []result.Finding{{Rule: "branch-name", Severity: "warning", Message: name}}, Guidance: g}
}
