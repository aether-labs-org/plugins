// Package check reports drift of the harness itself (spec section 13): warnings,
// never part of a gate verdict. It needs no plugin and no model.
package check

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/baseline"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/config"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/lock"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/memory"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/scope"
)

// Warning is one finding of bmax check.
type Warning struct{ ID, Message string }

// Options tunes a check. The zero value is what bmax check does.
type Options struct {
	// Measure, when set, is called for each baselined script to find baselines
	// that are stale because the measured counts fell (it runs the script).
	Measure func(script string) (map[string]int, error)
	Now     time.Time
}

// Thresholds.
const (
	maxAgentsLines   = 100
	maxProgressLines = 200
	planStaleDays    = 14
)

// Run checks the repository with the default options.
func Run(root string, cfg *config.Config, binaryVersion string) []Warning {
	return RunWith(root, cfg, binaryVersion, Options{})
}

func lineCount(b []byte) int {
	if len(b) == 0 {
		return 0
	}
	n := strings.Count(string(b), "\n")
	if b[len(b)-1] != '\n' {
		n++
	}
	return n
}

func read(root, rel string) ([]byte, bool) {
	b, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(rel)))
	return b, err == nil
}

func fileExists(root, rel string) bool {
	_, err := os.Stat(filepath.Join(root, filepath.FromSlash(rel)))
	return err == nil
}

var (
	bmaxRunRE  = regexp.MustCompile("`[^`\n]*?\\bbmax run ([A-Za-z0-9][A-Za-z0-9_-]*)[^`\n]*`")
	bmaxGateRE = regexp.MustCompile("`[^`\n]*?\\bbmax gate ([A-Za-z0-9][A-Za-z0-9_-]*)[^`\n]*`")
	linkRE     = regexp.MustCompile(`\]\(([^)\s]+)\)`)
	// a registered hook calls the wrapper: `.agents/bin/bmax" hook <event>` (the first v0.5 template) or the
	// round-3 form, which finds the wrapper with CLAUDE_PROJECT_DIR and runs `exec sh "$w" hook <event>`
	hookCmdRE  = regexp.MustCompile(`\.agents/bin/bmax"?\s+hook\s+`)
	hookCmdRE3 = regexp.MustCompile(`\.agents/bin/bmax\b[\s\S]*\bhook\s+(pre-tool-use|stop)\b`)
)

// RunWith is Run with options. Warnings come out in a stable order.
func RunWith(root string, cfg *config.Config, binaryVersion string, o Options) []Warning {
	if o.Now.IsZero() {
		o.Now = time.Now()
	}
	var ws []Warning
	add := func(id, format string, a ...any) { ws = append(ws, Warning{id, fmt.Sprintf(format, a...)}) }
	today := o.Now.Format("2006-01-02")

	// agents-size, agents-not-loaded, stale-command
	agents, hasAgents := read(root, "AGENTS.md")
	if hasAgents {
		if n := lineCount(agents); n > maxAgentsLines {
			add("agents-size", "AGENTS.md has %d lines; keep it an index of at most %d", n, maxAgentsLines)
		}
		seen := map[string]bool{}
		for _, m := range bmaxRunRE.FindAllStringSubmatch(string(agents), -1) {
			if _, ok := cfg.Scripts[m[1]]; !ok && !seen["run "+m[1]] {
				seen["run "+m[1]] = true
				add("stale-command", "AGENTS.md cites `bmax run %s` but bmax.yml declares no script %q", m[1], m[1])
			}
		}
		for _, m := range bmaxGateRE.FindAllStringSubmatch(string(agents), -1) {
			if _, ok := cfg.Gates[m[1]]; !ok && !seen["gate "+m[1]] {
				seen["gate "+m[1]] = true
				add("stale-command", "AGENTS.md cites `bmax gate %s` but bmax.yml declares no gate %q", m[1], m[1])
			}
		}
	}
	if claude, ok := read(root, "CLAUDE.md"); ok && !strings.Contains(string(claude), "@AGENTS.md") {
		add("agents-not-loaded", "CLAUDE.md does not contain @AGENTS.md, so Claude Code never loads AGENTS.md")
	}

	// dangling-pointer and guide-unlisted
	guides := append([]string(nil), cfg.Guides...)
	if hasAgents && !contains(guides, "AGENTS.md") {
		guides = append(guides, "AGENTS.md")
	}
	for _, g := range guides {
		b, ok := read(root, g)
		if !ok || !strings.HasSuffix(g, ".md") {
			continue
		}
		for _, m := range linkRE.FindAllStringSubmatch(string(b), -1) {
			t := m[1]
			if strings.Contains(t, "://") || strings.HasPrefix(t, "mailto:") || strings.HasPrefix(t, "#") {
				continue
			}
			t = strings.SplitN(t, "#", 2)[0]
			if t == "" {
				continue
			}
			var p string
			if strings.HasPrefix(t, "/") {
				p = strings.TrimPrefix(t, "/")
			} else {
				p = filepath.ToSlash(filepath.Join(filepath.Dir(g), t))
			}
			if !fileExists(root, p) {
				add("dangling-pointer", "%s links to %s, which does not exist", g, t)
			}
		}
	}
	if hasAgents {
		listed := map[string]bool{}
		for _, g := range cfg.Guides {
			listed[g] = true
		}
		seen := map[string]bool{}
		for _, m := range linkRE.FindAllStringSubmatch(string(agents), -1) {
			t := strings.SplitN(m[1], "#", 2)[0]
			t = filepath.ToSlash(filepath.Clean(t))
			if strings.HasPrefix(t, "docs/") && strings.HasSuffix(t, ".md") && !listed[t] && !seen[t] && fileExists(root, t) {
				seen[t] = true
				add("guide-unlisted", "AGENTS.md links %s, which is not in guides: so it is not protected", t)
			}
		}
	}

	// hook-missing
	settings, ok := read(root, ".claude/settings.json")
	var outdated []string
	for _, ev := range []string{"PreToolUse", "Stop"} {
		switch {
		case !ok || !hasHook(string(settings), ev):
			add("hook-missing", ".claude/settings.json has no %s hook calling .agents/bin/bmax hook", ev)
		case hookOutdated(string(settings), ev):
			outdated = append(outdated, ev)
		}
	}
	if len(outdated) > 0 {
		add("hook-outdated", ".claude/settings.json: the %s hook command finds the wrapper from the working directory only (no CLAUDE_PROJECT_DIR), so it breaks when a session moves into another repository; replace it with the command of the template", strings.Join(outdated, " and "))
	}

	// baselines, exceptions, requires, exemplars
	ids := append([]string(nil), cfg.Order...)
	sort.Strings(ids)
	for _, id := range ids {
		s := cfg.Scripts[id]
		if s.Baseline != "" {
			b, err := baseline.Read(filepath.Join(root, filepath.FromSlash(s.Baseline)))
			switch {
			case err != nil:
				add("baseline-malformed", "script %s: %s: %v", id, s.Baseline, trimPath(err.Error(), root))
			default:
				if b.ReviewBy != "" && b.ReviewBy < today {
					add("baseline-stale", "script %s: %s is past its review_by (%s); re-measure with bmax measure %s", id, s.Baseline, b.ReviewBy, id)
				}
				if o.Measure != nil {
					if counts, err := o.Measure(id); err == nil {
						var below []string
						for p, allowed := range b.Counts {
							if counts[p] < allowed {
								below = append(below, p)
							}
						}
						if len(below) > 0 {
							sort.Strings(below)
							add("baseline-stale", "script %s: the measured counts fell below %s for %s; propose bmax measure %s as the new baseline", id, s.Baseline, strings.Join(first(below, 3), ", "), id)
						}
					}
				}
			}
		}
		for _, e := range s.Exceptions {
			if e.Until < today {
				add("exception-expired", "script %s: the exception for %s expired on %s", id, e.Path, e.Until)
			}
		}
		for _, t := range s.Requires {
			if _, err := exec.LookPath(t); err != nil {
				add("script-unavailable", "script %s needs %s, which is not on PATH", id, t)
			}
		}
		for _, f := range []string{s.Exemplar, s.Legacy} {
			if f != "" && !fileExists(root, f) {
				add("exemplar-missing", "script %s names %s, which does not exist", id, f)
			}
		}
	}

	// run-state
	if tracked := gitOut(root, "ls-files", ".agents/run"); strings.TrimSpace(tracked) != "" {
		add("run-state", ".agents/run/ has tracked files; evidence and local state must not be committed")
	} else if _, err := scope.Git(root, "check-ignore", "-q", ".agents/run/x"); err != nil {
		add("run-state", ".agents/run/ is not git-ignored; add it to .gitignore")
	}

	// review-due
	if cfg.ReviewDue != "" && cfg.ReviewDue < today {
		add("review-due", "the harness review was due on %s", cfg.ReviewDue)
	}

	// memory: plan-stale, progress-size, memory-malformed
	plans, _, _ := memory.ActivePlans(root)
	for _, p := range plans {
		if age := fileAgeDays(root, p.Path, o.Now); age > planStaleDays {
			add("plan-stale", "%s has not changed for %d days; close it (delete it and add a line to .agents/progress.md) or update it", p.Path, age)
		}
	}
	if b, ok := read(root, ".agents/progress.md"); ok && lineCount(b) > maxProgressLines {
		add("progress-size", ".agents/progress.md has %d lines; keep at most %d (archive the old ones)", lineCount(b), maxProgressLines)
	}
	if _, issues, err := memory.All(root); err == nil {
		for _, i := range issues {
			add("memory-malformed", "%s:%d: %s", i.File, i.Line, i.Msg)
		}
	}

	// githooks-inactive
	ws = append(ws, githooks(root, cfg)...)

	// reviewer-missing: the checklist, and a reviewer for at least one of the agents in use
	{
		var missing []string
		if !fileExists(root, "docs/review.md") {
			missing = append(missing, "docs/review.md")
		}
		if !fileExists(root, ".claude/agents/baymax-reviewer.md") && !fileExists(root, ".github/agents/baymax-reviewer.agent.md") {
			missing = append(missing, "a reviewer agent (.claude/agents/baymax-reviewer.md for Claude Code or .github/agents/baymax-reviewer.agent.md for Copilot CLI)")
		}
		if len(missing) > 0 {
			add("reviewer-missing", "missing: %s", strings.Join(missing, ", "))
		}
	}

	// harness-ignored: a harness file git ignores is not versioned, so nobody gets it on a clone
	for _, f := range harnessFiles(root, cfg) {
		if _, err := scope.Git(root, "check-ignore", "-q", "--", f); err == nil {
			out := strings.TrimSpace(gitOut(root, "check-ignore", "-v", "--", f))
			rule := out
			if i := strings.IndexByte(out, '\t'); i >= 0 {
				rule = out[:i]
			}
			add("harness-ignored", "%s exists but git ignores it (%s), so it is not versioned; narrow the rule in .gitignore", f, rule)
		}
	}

	// pin-mismatch
	if l, err := lock.Read(filepath.Join(root, ".agents", "bmax.lock")); err == nil {
		if err := lock.Check(l, binaryVersion); err != nil {
			add("pin-mismatch", "%v", err)
		}
	}
	return ws
}

// harnessFiles lists the harness files that exist, in a stable order.
func harnessFiles(root string, cfg *config.Config) []string {
	cands := []string{".agents/bmax.yml", ".agents/bmax.lock", ".agents/bin/bmax", "AGENTS.md", "CLAUDE.md", "docs/review.md",
		".claude/settings.json", ".claude/agents/baymax-reviewer.md", ".github/agents/baymax-reviewer.agent.md"}
	if ents, err := os.ReadDir(filepath.Join(root, ".agents", "githooks")); err == nil {
		for _, e := range ents {
			if !e.IsDir() {
				cands = append(cands, ".agents/githooks/"+e.Name())
			}
		}
	}
	cands = append(cands, cfg.Guides...)
	seen := map[string]bool{}
	var out []string
	for _, f := range cands {
		if !seen[f] && fileExists(root, f) {
			seen[f] = true
			out = append(out, f)
		}
	}
	sort.Strings(out)
	return out
}

func contains(l []string, s string) bool {
	for _, x := range l {
		if x == s {
			return true
		}
	}
	return false
}

func first(l []string, n int) []string {
	if len(l) > n {
		return l[:n]
	}
	return l
}

func trimPath(msg, root string) string { return strings.ReplaceAll(msg, root+"/", "") }

func gitOut(root string, args ...string) string {
	out, err := scope.Git(root, args...)
	if err != nil {
		return ""
	}
	return string(out)
}

func hookCommands(settings, event string) []string {
	var doc struct {
		Hooks map[string][]struct {
			Hooks []struct {
				Command string `json:"command"`
			} `json:"hooks"`
		} `json:"hooks"`
	}
	if json.Unmarshal([]byte(settings), &doc) != nil {
		return nil
	}
	var out []string
	for _, g := range doc.Hooks[event] {
		for _, h := range g.Hooks {
			out = append(out, h.Command)
		}
	}
	return out
}

// hasHook reports whether settings.json registers a command under the event
// that calls the wrapper's hook (.agents/bin/bmax hook <event>), in either form.
func hasHook(settings, event string) bool {
	for _, c := range hookCommands(settings, event) {
		if hookCmdRE.MatchString(c) || hookCmdRE3.MatchString(c) {
			return true
		}
	}
	return false
}

// hookOutdated: a registered hook calls the wrapper directly, without
// CLAUDE_PROJECT_DIR, and no other registered command uses it.
func hookOutdated(settings, event string) bool {
	cmds := hookCommands(settings, event)
	for _, c := range cmds {
		if strings.Contains(c, "CLAUDE_PROJECT_DIR") && hookCmdRE3.MatchString(c) {
			return false
		}
	}
	for _, c := range cmds {
		if hookCmdRE.MatchString(c) {
			return true
		}
	}
	return false
}

func fileAgeDays(root, rel string, now time.Time) int {
	var mod time.Time
	if out := strings.TrimSpace(gitOut(root, "log", "-1", "--format=%ct", "--", rel)); out != "" {
		var sec int64
		if _, err := fmt.Sscanf(out, "%d", &sec); err == nil {
			mod = time.Unix(sec, 0)
		}
	}
	if mod.IsZero() {
		if st, err := os.Stat(filepath.Join(root, filepath.FromSlash(rel))); err == nil {
			mod = st.ModTime()
		}
	}
	if mod.IsZero() {
		return 0
	}
	return int(now.Sub(mod).Hours() / 24)
}

var managerConfigs = []string{".husky/pre-commit", ".husky/pre-push", ".husky/commit-msg", "lefthook.yml", "lefthook.yaml", ".lefthook.yml", ".pre-commit-config.yaml", "package.json", ".simple-git-hooks.json"}

func githooks(root string, cfg *config.Config) []Warning {
	g := cfg.Githooks
	if g.Mode == "" && g.PreCommit == "" && g.PrePush == "" && g.CommitMsg == "" {
		return nil
	}
	if g.Mode == "external" {
		for _, f := range managerConfigs {
			if b, ok := read(root, f); ok && strings.Contains(string(b), ".agents/bin/bmax") {
				return nil
			}
		}
		return []Warning{{"githooks-inactive", "githooks.mode is external but no hook manager config (husky, lefthook, pre-commit) calls .agents/bin/bmax"}}
	}
	got := strings.TrimSpace(gitOut(root, "config", "--get", "core.hooksPath"))
	if strings.TrimSuffix(got, "/") != ".agents/githooks" {
		return []Warning{{"githooks-inactive", "core.hooksPath is not .agents/githooks; run sh .agents/bin/bmax setup"}}
	}
	return nil
}
