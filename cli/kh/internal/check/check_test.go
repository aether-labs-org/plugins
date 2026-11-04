package check

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/aether-labs-org/plugins/cli/kh/internal/builtin"
	"github.com/aether-labs-org/plugins/cli/kh/internal/config"
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

const cleanKeel = `version: 1
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

const hookSettings = `{"hooks":{"PreToolUse":[{"matcher":"Write|Edit|Bash","hooks":[{"type":"command","command":"sh \"$(git rev-parse --show-toplevel)/.agents/bin/kh\" hook pre-tool-use","timeout":10}]}],"Stop":[{"hooks":[{"type":"command","command":"sh \"$(git rev-parse --show-toplevel)/.agents/bin/kh\" hook stop","timeout":120}]}]}}`

const agentsMD = "# Project\n\nSetup: `sh .agents/bin/kh setup`\nRun: `sh .agents/bin/kh run test`, `sh .agents/bin/kh gate fast`\n\nSee [testing](docs/testing.md).\n"

// clean builds a repository that has zero warnings.
func clean(t *testing.T) (string, *config.Config) {
	t.Helper()
	d, _ := filepath.EvalSymlinks(t.TempDir())
	git(t, d, "init", "-q", ".")
	write(t, d, ".gitignore", ".agents/run/\n")
	write(t, d, ".agents/keel.yml", cleanKeel)
	write(t, d, ".agents/baselines/lint.tsv", "# measured_at: 2026-11-01 review_by: 2999-01-01\nsrc/a.ts\t3\n")
	write(t, d, "AGENTS.md", agentsMD)
	write(t, d, "CLAUDE.md", "@AGENTS.md\n")
	write(t, d, "docs/review.md", "# review\n")
	write(t, d, "docs/testing.md", "# testing\n")
	write(t, d, "src/good.ts", "export {}\n")
	write(t, d, ".claude/settings.json", hookSettings)
	write(t, d, ".claude/agents/keel-reviewer.md", "---\nname: keel-reviewer\n---\n")
	write(t, d, ".github/agents/keel-reviewer.agent.md", "---\nname: keel-reviewer\n---\n")
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
		{"stale-command run", "stale-command", `kh run lnt`, func(t *testing.T, d string) {
			write(t, d, "AGENTS.md", agentsMD+"Lint with `sh .agents/bin/kh run lnt`.\n")
		}},
		{"stale-command gate", "stale-command", `kh gate nightly`, func(t *testing.T, d string) { write(t, d, "AGENTS.md", agentsMD+"Run `kh gate nightly`.\n") }},
		{"dangling-pointer", "dangling-pointer", "docs/gone.md", func(t *testing.T, d string) { write(t, d, "AGENTS.md", agentsMD+"Also [gone](docs/gone.md#x).\n") }},
		{"dangling-pointer in a guide", "dangling-pointer", "../nope.md", func(t *testing.T, d string) { write(t, d, "docs/testing.md", "# t\n[up](../nope.md)\n") }},
		{"hook-missing Stop", "hook-missing", "Stop", func(t *testing.T, d string) {
			write(t, d, ".claude/settings.json", `{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"sh .agents/bin/kh hook pre-tool-use"}]}]}}`)
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
			write(t, d, ".agents/keel.yml", strings.Replace(cleanKeel, "until: 2999-01-01", "until: 2020-01-01", 1))
		}},
		{"script-unavailable", "script-unavailable", "definitely-missing-tool", func(t *testing.T, d string) {
			write(t, d, ".agents/keel.yml", strings.Replace(cleanKeel, "  test: { run: \"true\" }", "  test: { run: \"true\", requires: [definitely-missing-tool] }", 1))
		}},
		{"run-state untracked", "run-state", "not git-ignored", func(t *testing.T, d string) { write(t, d, ".gitignore", "node_modules/\n") }},
		{"run-state tracked", "run-state", "tracked files", func(t *testing.T, d string) {
			write(t, d, ".agents/run/runs/x/meta.json", "{}")
			git(t, d, "add", "-f", ".agents/run/runs/x/meta.json")
		}},
		{"review-due", "review-due", "2020-01-01", func(t *testing.T, d string) {
			write(t, d, ".agents/keel.yml", strings.Replace(cleanKeel, "review_due: 2999-01-01", "review_due: 2020-01-01", 1))
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
		{"reviewer-missing", "reviewer-missing", ".github/agents/keel-reviewer.agent.md", func(t *testing.T, d string) {
			os.Remove(filepath.Join(d, ".github/agents/keel-reviewer.agent.md"))
		}},
		{"guide-unlisted", "guide-unlisted", "docs/extra.md", func(t *testing.T, d string) {
			write(t, d, "docs/extra.md", "# extra\n")
			write(t, d, "AGENTS.md", agentsMD+"More in [extra](docs/extra.md).\n")
		}},
		{"pin-mismatch", "pin-mismatch", "pin mismatch: keel.lock pins 0.5.1, this kh is 0.5.0", func(t *testing.T, d string) {
			l := "version=0.5.1\n"
			for _, p := range []string{"linux-amd64", "linux-arm64", "darwin-amd64", "darwin-arm64"} {
				l += p + "=" + strings.Repeat("a", 64) + "\n"
			}
			write(t, d, ".agents/keel.lock", l)
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

func TestGithooksExternal(t *testing.T) {
	d, _ := clean(t)
	write(t, d, ".agents/keel.yml", strings.Replace(cleanKeel, "mode: native", "mode: external", 1))
	git(t, d, "config", "--unset", "core.hooksPath")
	cfg := load(t, d)
	only(t, Run(d, cfg, "0.5.0"), "githooks-inactive", "no hook manager config")
	write(t, d, ".husky/pre-commit", "#!/bin/sh\nsh .agents/bin/kh gate commit\n")
	if ws := Run(d, cfg, "0.5.0"); len(ws) != 0 {
		t.Fatalf("%v", ws)
	}
}

func TestGithooksNotAdopted(t *testing.T) {
	d, _ := clean(t)
	write(t, d, ".agents/keel.yml", strings.Replace(cleanKeel, "githooks: { mode: native, pre-commit: commit, pre-push: slow }\n", "", 1))
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
	write(t, d, ".agents/keel.yml", strings.Replace(cleanKeel, "fast: { scripts: [guard, lint] }", "fast: { scripts: [lint] }", 1))
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
