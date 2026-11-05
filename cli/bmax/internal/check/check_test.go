package check

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/builtin"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/config"
)

func git(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false"}, args...)...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

func write(t *testing.T, dir, name, body string) {
	t.Helper()
	p := filepath.Join(dir, name)
	os.MkdirAll(filepath.Dir(p), 0o755)
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

const cleanBmax = `version: 1
review_due: 2999-01-01
guides: [AGENTS.md, CLAUDE.md, docs/review.md, docs/testing.md]
githooks: { mode: native, pre-commit: commit, pre-push: slow }
scripts:
  test: { run: "true" }
  lint:
    run: "true"
    format: eslint-json
    class: heuristic
    baseline: .agents/baselines/lint.tsv
    exceptions: [ { path: "legacy/**", until: 2999-01-01 } ]
    exemplar: src/good.ts
gates:
  fast: { scripts: [guard, lint] }
  commit: { scripts: [guard, lint], changes: staged }
  slow: { scripts: [guard, test], changes: branch }
`

// the hook commands of the settings.json template (round 3): the wrapper is located with CLAUDE_PROJECT_DIR
func hookCommand(event string) string {
	return `w=\"${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}/.agents/bin/bmax\"; if [ -f \"$w\" ]; then exec sh \"$w\" hook ` + event + `; fi; printf '%s\\n' '{}'`
}

var hookSettings = `{"hooks":{"PreToolUse":[{"matcher":"Write|Edit|Bash","hooks":[{"type":"command","command":"` + hookCommand("pre-tool-use") + `","timeout":10}]}],"Stop":[{"hooks":[{"type":"command","command":"` + hookCommand("stop") + `","timeout":120}]}]}}`

// the commands of the first v0.5 template: they resolve the wrapper from the working directory only
const oldHookSettings = `{"hooks":{"PreToolUse":[{"matcher":"Write|Edit|Bash","hooks":[{"type":"command","command":"sh \"$(git rev-parse --show-toplevel)/.agents/bin/bmax\" hook pre-tool-use","timeout":10}]}],"Stop":[{"hooks":[{"type":"command","command":"sh \"$(git rev-parse --show-toplevel)/.agents/bin/bmax\" hook stop","timeout":120}]}]}}`

const agentsMD = "# Project\n\nSetup: `sh .agents/bin/bmax setup`\nRun: `sh .agents/bin/bmax run test`, `sh .agents/bin/bmax gate fast`\n\nSee [testing](docs/testing.md).\n"

// clean builds a repository that has zero warnings.
func clean(t *testing.T) (string, *config.Config) {
	t.Helper()
	d, _ := filepath.EvalSymlinks(t.TempDir())
	git(t, d, "init", "-q", ".")
	write(t, d, ".gitignore", ".agents/run/\n")
	write(t, d, ".agents/bmax.yml", cleanBmax)
	write(t, d, ".agents/baselines/lint.tsv", "# measured_at: 2026-11-01 review_by: 2999-01-01\nsrc/a.ts\t3\n")
	write(t, d, "AGENTS.md", agentsMD)
	write(t, d, "CLAUDE.md", "@AGENTS.md\n")
	write(t, d, "docs/review.md", "# review\n")
	write(t, d, "docs/testing.md", "# testing\n")
	write(t, d, "src/good.ts", "export {}\n")
	write(t, d, ".claude/settings.json", hookSettings)
	write(t, d, ".claude/agents/baymax-reviewer.md", "---\nname: baymax-reviewer\n---\n")
	write(t, d, ".github/agents/baymax-reviewer.agent.md", "---\nname: baymax-reviewer\n---\n")
	git(t, d, "add", "-A")
	git(t, d, "commit", "-q", "-m", "seed")
	git(t, d, "config", "core.hooksPath", ".agents/githooks")
	return d, load(t, d)
}

func load(t *testing.T, d string) *config.Config {
	t.Helper()
	c, err := config.LoadValid(d, builtin.Default().Validator())
	if err != nil {
		t.Fatalf("config: %v", err)
	}
	return c
}

func ids(ws []Warning) []string {
	var out []string
	for _, w := range ws {
		out = append(out, w.ID)
	}
	return out
}

func TestCleanRepoNoWarnings(t *testing.T) {
	d, cfg := clean(t)
	if ws := Run(d, cfg, "0.5.0"); len(ws) != 0 {
		t.Fatalf("%v", ws)
	}
}

func only(t *testing.T, ws []Warning, id, contains string) {
	t.Helper()
	if len(ws) != 1 || ws[0].ID != id || !strings.Contains(ws[0].Message, contains) {
		t.Fatalf("want exactly %s containing %q, got %v", id, contains, ws)
	}
}

func TestEachWarning(t *testing.T) {
	cases := []struct {
		name, id, contains string
		mutate             func(t *testing.T, d string)
	}{
		{"agents-size", "agents-size", "101 lines", func(t *testing.T, d string) { write(t, d, "AGENTS.md", agentsMD+strings.Repeat("filler\n", 95)) }},
		{"agents-not-loaded", "agents-not-loaded", "@AGENTS.md", func(t *testing.T, d string) { write(t, d, "CLAUDE.md", "# my own rules\n") }},
		{"stale-command run", "stale-command", `bmax run lnt`, func(t *testing.T, d string) {
			write(t, d, "AGENTS.md", agentsMD+"Lint with `sh .agents/bin/bmax run lnt`.\n")
		}},
		{"stale-command gate", "stale-command", `bmax gate nightly`, func(t *testing.T, d string) { write(t, d, "AGENTS.md", agentsMD+"Run `bmax gate nightly`.\n") }},
		{"dangling-pointer", "dangling-pointer", "docs/gone.md", func(t *testing.T, d string) { write(t, d, "AGENTS.md", agentsMD+"Also [gone](docs/gone.md#x).\n") }},
		{"dangling-pointer in a guide", "dangling-pointer", "../nope.md", func(t *testing.T, d string) { write(t, d, "docs/testing.md", "# t\n[up](../nope.md)\n") }},
		{"hook-missing Stop", "hook-missing", "Stop", func(t *testing.T, d string) {
			write(t, d, ".claude/settings.json", `{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"`+hookCommand("pre-tool-use")+`"}]}]}}`)
		}},
		{"hook-outdated", "hook-outdated", "CLAUDE_PROJECT_DIR", func(t *testing.T, d string) { write(t, d, ".claude/settings.json", oldHookSettings) }},
		{"harness-ignored", "harness-ignored", "docs/review.md", func(t *testing.T, d string) {
			write(t, d, ".gitignore", ".agents/run/\ndocs/review.md\n")
			git(t, d, "rm", "-q", "--cached", "docs/review.md")
		}},
		{"baseline-stale review_by", "baseline-stale", "past its review_by", func(t *testing.T, d string) {
			write(t, d, ".agents/baselines/lint.tsv", "# measured_at: 2024-01-01 review_by: 2024-07-01\nsrc/a.ts\t3\n")
		}},
		{"baseline-malformed", "baseline-malformed", "line 2", func(t *testing.T, d string) {
			write(t, d, ".agents/baselines/lint.tsv", "# measured_at: 2026-11-01 review_by: 2999-01-01\nsrc/a.ts\tx\n")
		}},
		{"baseline missing", "baseline-malformed", "lint.tsv", func(t *testing.T, d string) {
			os.Remove(filepath.Join(d, ".agents/baselines/lint.tsv"))
		}},
		{"exception-expired", "exception-expired", "legacy/**", func(t *testing.T, d string) {
			write(t, d, ".agents/bmax.yml", strings.Replace(cleanBmax, "until: 2999-01-01", "until: 2020-01-01", 1))
		}},
		{"script-unavailable", "script-unavailable", "definitely-missing-tool", func(t *testing.T, d string) {
			write(t, d, ".agents/bmax.yml", strings.Replace(cleanBmax, "  test: { run: \"true\" }", "  test: { run: \"true\", requires: [definitely-missing-tool] }", 1))
		}},
		{"run-state untracked", "run-state", "not git-ignored", func(t *testing.T, d string) { write(t, d, ".gitignore", "node_modules/\n") }},
		{"run-state tracked", "run-state", "tracked files", func(t *testing.T, d string) {
			write(t, d, ".agents/run/runs/x/meta.json", "{}")
			git(t, d, "add", "-f", ".agents/run/runs/x/meta.json")
		}},
		{"review-due", "review-due", "2020-01-01", func(t *testing.T, d string) {
			write(t, d, ".agents/bmax.yml", strings.Replace(cleanBmax, "review_due: 2999-01-01", "review_due: 2020-01-01", 1))
		}},
		{"exemplar-missing", "exemplar-missing", "src/good.ts", func(t *testing.T, d string) { os.Remove(filepath.Join(d, "src/good.ts")) }},
		{"progress-size", "progress-size", "201 lines", func(t *testing.T, d string) {
			write(t, d, ".agents/progress.md", strings.Repeat("- 2026-11-04 s: done — x\n", 201))
		}},
		{"memory-malformed", "memory-malformed", ".agents/lessons.md:1", func(t *testing.T, d string) {
			write(t, d, ".agents/lessons.md", "## nonsense heading\n")
		}},
		{"githooks-inactive native", "githooks-inactive", "core.hooksPath", func(t *testing.T, d string) {
			git(t, d, "config", "--unset", "core.hooksPath")
		}},
		{"reviewer-missing: no review.md", "reviewer-missing", "docs/review.md", func(t *testing.T, d string) {
			os.Remove(filepath.Join(d, "docs/review.md"))
			write(t, d, ".agents/bmax.yml", strings.Replace(cleanBmax, "docs/review.md, ", "", 1))
		}},
		{"reviewer-missing: no reviewer agent", "reviewer-missing", "baymax-reviewer", func(t *testing.T, d string) {
			os.Remove(filepath.Join(d, ".claude/agents/baymax-reviewer.md"))
			os.Remove(filepath.Join(d, ".github/agents/baymax-reviewer.agent.md"))
		}},
		{"guide-unlisted", "guide-unlisted", "docs/extra.md", func(t *testing.T, d string) {
			write(t, d, "docs/extra.md", "# extra\n")
			write(t, d, "AGENTS.md", agentsMD+"More in [extra](docs/extra.md).\n")
		}},
		{"pin-mismatch", "pin-mismatch", "pin mismatch: bmax.lock pins 0.5.1, this bmax is 0.5.0", func(t *testing.T, d string) {
			l := "version=0.5.1\n"
			for _, p := range []string{"linux-amd64", "linux-arm64", "darwin-amd64", "darwin-arm64"} {
				l += p + "=" + strings.Repeat("a", 64) + "\n"
			}
			write(t, d, ".agents/bmax.lock", l)
		}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			d, _ := clean(t)
			c.mutate(t, d)
			cfg, err := config.LoadValid(d, builtin.Default().Validator())
			if err != nil {
				t.Fatal(err)
			}
			only(t, Run(d, cfg, "0.5.0"), c.id, c.contains)
		})
	}
}

func TestHarnessIgnoredNamesEveryFileAndTheRule(t *testing.T) {
	d, cfg := clean(t)
	write(t, d, ".gitignore", ".agents/run/\n.claude/\n")
	git(t, d, "rm", "-q", "--cached", "-r", ".claude")
	ws := Run(d, cfg, "0.5.0")
	var got []string
	for _, w := range ws {
		if w.ID != "harness-ignored" {
			t.Fatalf("unexpected %v", w)
		}
		got = append(got, w.Message)
	}
	if len(got) != 2 || !strings.Contains(got[0], ".claude/agents/baymax-reviewer.md") || !strings.Contains(got[1], ".claude/settings.json") || !strings.Contains(got[1], ".gitignore:2:.claude/") {
		t.Fatalf("%q", got)
	}
	// hook-missing is not reported for an ignored settings.json that exists; narrowing the rule clears the warnings
	write(t, d, ".gitignore", ".agents/run/\n.claude/*\n!.claude/settings.json\n!.claude/agents/\n")
	if ws := Run(d, cfg, "0.5.0"); len(ws) != 0 {
		t.Fatalf("%v", ws)
	}
}

func TestHarnessIgnoredTrackedFilesAreVersioned(t *testing.T) {
	d, cfg := clean(t)
	write(t, d, ".gitignore", ".agents/run/\nAGENTS.md\n") // AGENTS.md is tracked: git still versions it
	if ws := Run(d, cfg, "0.5.0"); len(ws) != 0 {
		t.Fatalf("%v", ws)
	}
}

// a team that uses one agent needs one reviewer file, not both
func TestReviewerNeedsAtLeastOneAgentFile(t *testing.T) {
	for _, keep := range []string{".claude/agents/baymax-reviewer.md", ".github/agents/baymax-reviewer.agent.md"} {
		d, cfg := clean(t)
		for _, f := range []string{".claude/agents/baymax-reviewer.md", ".github/agents/baymax-reviewer.agent.md"} {
			if f != keep {
				os.Remove(filepath.Join(d, f))
			}
		}
		if ws := Run(d, cfg, "0.5.0"); len(ws) != 0 {
			t.Errorf("only %s: %v", keep, ws)
		}
	}
}

func TestGithooksExternal(t *testing.T) {
	d, _ := clean(t)
	write(t, d, ".agents/bmax.yml", strings.Replace(cleanBmax, "mode: native", "mode: external", 1))
	git(t, d, "config", "--unset", "core.hooksPath")
	cfg := load(t, d)
	only(t, Run(d, cfg, "0.5.0"), "githooks-inactive", "no hook manager config")
	write(t, d, ".husky/pre-commit", "#!/bin/sh\nsh .agents/bin/bmax gate commit\n")
	if ws := Run(d, cfg, "0.5.0"); len(ws) != 0 {
		t.Fatalf("%v", ws)
	}
}

func TestGithooksNotAdopted(t *testing.T) {
	d, _ := clean(t)
	write(t, d, ".agents/bmax.yml", strings.Replace(cleanBmax, "githooks: { mode: native, pre-commit: commit, pre-push: slow }\n", "", 1))
	git(t, d, "config", "--unset", "core.hooksPath")
	if ws := Run(d, load(t, d), "0.5.0"); len(ws) != 0 {
		t.Fatalf("%v", ws)
	}
}

func TestPlanStale(t *testing.T) {
	d, cfg := clean(t)
	write(t, d, ".agents/plans/p.md", "# P\n\nStatus: active\nScope: src/**\n\n## Acceptance\n- [ ] x\n")
	git(t, d, "add", "-A")
	git(t, d, "commit", "-q", "-m", "plan")
	if ws := Run(d, cfg, "0.5.0"); len(ws) != 0 {
		t.Fatalf("fresh plan: %v", ws)
	}
	ws := RunWith(d, cfg, "0.5.0", Options{Now: time.Now().AddDate(0, 0, 15)})
	only(t, ws, "plan-stale", ".agents/plans/p.md has not changed for 15 days")
}

func TestBaselineStaleByMeasure(t *testing.T) {
	d, cfg := clean(t)
	ws := RunWith(d, cfg, "0.5.0", Options{Measure: func(id string) (map[string]int, error) { return map[string]int{"src/a.ts": 1}, nil }})
	only(t, ws, "baseline-stale", "fell below")
	ws = RunWith(d, cfg, "0.5.0", Options{Measure: func(id string) (map[string]int, error) { return map[string]int{"src/a.ts": 3}, nil }})
	if len(ws) != 0 {
		t.Fatalf("equal counts: %v", ws)
	}
}

func TestGuardMissingIsAValidateIssue(t *testing.T) {
	d, _ := clean(t)
	write(t, d, ".agents/bmax.yml", strings.Replace(cleanBmax, "fast: { scripts: [guard, lint] }", "fast: { scripts: [lint] }", 1))
	_, err := config.LoadValid(d, builtin.Default().Validator())
	if err == nil || !strings.Contains(err.Error(), `gate "fast" must list guard`) {
		t.Fatalf("%v", err)
	}
}

func TestHookMissingWithoutSettings(t *testing.T) {
	d, cfg := clean(t)
	os.Remove(filepath.Join(d, ".claude/settings.json"))
	ws := Run(d, cfg, "0.5.0")
	if len(ws) != 2 || ws[0].ID != "hook-missing" || ws[1].ID != "hook-missing" {
		t.Fatalf("%v", ws)
	}
}
