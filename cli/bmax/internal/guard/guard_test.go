package guard

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
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

const baseBmax = `version: 1
guides: [AGENTS.md, docs/review.md]
githooks: { mode: native, pre-commit: commit, pre-push: slow }
scripts:
  lint:
    run: eslint
    format: eslint-json
    class: heuristic
    timeout: 5m
    retries: 1
    files: "*.ts"
    decision: docs/adr/0001-lint.md
    config: [eslint.config.js]
    baseline: .agents/baselines/lint.tsv
    exceptions:
      - { path: "a/*", until: 2027-01-01 }
  fs:
    builtin: file-size
    class: heuristic
    baseline: .agents/baselines/fs.tsv
    decision: docs/adr/0002-fs.md
    with: { limit: 300 }
  sec: { run: gitleaks, class: security, format: sarif }
  tc: { run: tsc }
gates:
  fast: { scripts: [guard, lint, fs, sec, tc], ceiling: 30s }
  commit: { scripts: [guard, lint, sec], changes: staged, ceiling: 30s }
  slow: { scripts: [guard, lint, tc], changes: branch, ceiling: 10m }
`

const hookSettings = `{"hooks":{"PreToolUse":[{"matcher":"Write|Edit|Bash","hooks":[{"type":"command","command":"sh \"$(git rev-parse --show-toplevel)/.agents/bin/bmax\" hook pre-tool-use","timeout":10}]}],"Stop":[{"hooks":[{"type":"command","command":"sh \"$(git rev-parse --show-toplevel)/.agents/bin/bmax\" hook stop","timeout":120}]}]}}`

// harness makes a committed repository with a v0.5 harness and returns it with
// the base commit.
func harness(t *testing.T) (string, string) {
	t.Helper()
	d, _ := filepath.EvalSymlinks(t.TempDir())
	t.Setenv("BMAX_GUARD_BASE", "")
	git(t, d, "init", "-q", ".")
	write(t, d, ".agents/bmax.yml", baseBmax)
	write(t, d, ".agents/baselines/lint.tsv", "# measured_at: 2026-11-01 review_by: 2027-05-01\na.ts\t3\nb.ts\t1\n")
	write(t, d, ".agents/baselines/fs.tsv", "# measured_at: 2026-11-01 review_by: 2027-05-01\nbig.ts\t400\n")
	write(t, d, "AGENTS.md", "# agents\n")
	write(t, d, "docs/review.md", "# review\n")
	write(t, d, "eslint.config.js", "export default []\n")
	write(t, d, "docs/adr/0001-lint.md", "# 1. Lint\n\nStatus: accepted\n\nWe lint.\n")
	write(t, d, "docs/adr/0002-fs.md", "---\nstatus: accepted\n---\n# 2. File size\n")
	write(t, d, "docs/adr/0003-draft.md", "# 3. Draft\n\nStatus: proposed\n")
	write(t, d, ".claude/settings.json", hookSettings)
	write(t, d, "tsconfig.json", "{ \"compilerOptions\": { \"strict\": true } }\n")
	git(t, d, "add", "-A")
	git(t, d, "commit", "-q", "-m", "base")
	return d, git(t, d, "rev-parse", "HEAD")
}

func sub(t *testing.T, d, file, old, new string) {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(d, file))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(b), old) {
		t.Fatalf("%s lacks %q", file, old)
	}
	write(t, d, file, strings.Replace(string(b), old, new, 1))
}

func check(t *testing.T, d, base string) (v, rel []Loosening) {
	t.Helper()
	v, rel, err := Check(d, base)
	if err != nil {
		t.Fatalf("Check: %v", err)
	}
	return v, rel
}

func whats(ls []Loosening) string {
	var s []string
	for _, l := range ls {
		s = append(s, l.Target+": "+l.What)
	}
	return strings.Join(s, "\n")
}

func TestNothingChanged(t *testing.T) {
	d, base := harness(t)
	if v, r := check(t, d, base); len(v) != 0 || len(r) != 0 {
		t.Fatalf("%s", whats(v))
	}
}

// Each loosening fails without an ADR and passes with one that names the target.
func TestEveryLooseningNeedsAnADR(t *testing.T) {
	cases := []struct {
		name   string
		mutate func(t *testing.T, d string)
		what   string // substring of What
		target string // expected Target
	}{
		{"removed from gate", func(t *testing.T, d string) {
			sub(t, d, ".agents/bmax.yml", "fast: { scripts: [guard, lint, fs, sec, tc]", "fast: { scripts: [guard, lint, fs, tc]")
		}, "removed from gate fast", ".agents/bmax.yml#sec"},
		{"guard removed from a gate", func(t *testing.T, d string) {
			sub(t, d, ".agents/bmax.yml", "commit: { scripts: [guard, lint, sec]", "commit: { scripts: [lint, sec]")
		}, "removed from gate commit", ".agents/bmax.yml#guard"},
		{"timeout raised", func(t *testing.T, d string) { sub(t, d, ".agents/bmax.yml", "timeout: 5m", "timeout: 20m") }, "timeout raised 5m -> 20m", ".agents/bmax.yml#lint"},
		{"ceiling raised", func(t *testing.T, d string) {
			sub(t, d, ".agents/bmax.yml", "ceiling: 30s }\n  commit", "ceiling: 90s }\n  commit")
		}, "ceiling raised", ".agents/bmax.yml#fast"},
		{"ceiling removed", func(t *testing.T, d string) { sub(t, d, ".agents/bmax.yml", ", ceiling: 10m", "") }, "ceiling raised", ".agents/bmax.yml#slow"},
		{"retries raised", func(t *testing.T, d string) { sub(t, d, ".agents/bmax.yml", "retries: 1", "retries: 3") }, "retries raised", ".agents/bmax.yml#lint"},
		{"class changed from security", func(t *testing.T, d string) {
			sub(t, d, ".agents/bmax.yml", "sec: { run: gitleaks, class: security", "sec: { run: gitleaks, class: heuristic")
		}, "class changed from security", ".agents/bmax.yml#sec"},
		{"class dropped", func(t *testing.T, d string) {
			sub(t, d, ".agents/bmax.yml", "sec: { run: gitleaks, class: security, ", "sec: { run: gitleaks, ")
		}, "class changed from security", ".agents/bmax.yml#sec"},
		{"files narrowed", func(t *testing.T, d string) { sub(t, d, ".agents/bmax.yml", `files: "*.ts"`, `files: "src/a.ts"`) }, "files narrowed", ".agents/bmax.yml#lint"},
		{"files added", func(t *testing.T, d string) {
			sub(t, d, ".agents/bmax.yml", "tc: { run: tsc }", `tc: { run: tsc, files: "x.ts" }`)
		}, "files narrowed", ".agents/bmax.yml#tc"},
		{"format removed", func(t *testing.T, d string) { sub(t, d, ".agents/bmax.yml", "    format: eslint-json\n", "") }, "format removed", ".agents/bmax.yml#lint"},
		{"run changed with decision", func(t *testing.T, d string) {
			sub(t, d, ".agents/bmax.yml", "run: eslint\n", "run: eslint --max-warnings 9999\n")
		}, "run changed on a script with decision", ".agents/bmax.yml#lint"},
		{"with changed with decision", func(t *testing.T, d string) {
			sub(t, d, ".agents/bmax.yml", "with: { limit: 300 }", "with: { limit: 9000 }")
		}, "with changed on a script with decision", ".agents/bmax.yml#fs"},
		{"baseline row grown", func(t *testing.T, d string) { sub(t, d, ".agents/baselines/lint.tsv", "a.ts\t3", "a.ts\t9") }, "baseline row grown a.ts 3 -> 9", ".agents/baselines/lint.tsv"},
		{"baseline row added", func(t *testing.T, d string) {
			write(t, d, ".agents/baselines/file-size.tsv", "")
			os.Remove(filepath.Join(d, ".agents/baselines/file-size.tsv"))
			sub(t, d, ".agents/baselines/fs.tsv", "big.ts\t400\n", "big.ts\t400\nnew.ts\t310\n")
		}, "baseline row added new.ts", ".agents/baselines/fs.tsv"},
		{"D1 reproduction", func(t *testing.T, d string) {
			b, _ := os.ReadFile(filepath.Join(d, ".agents/baselines/fs.tsv"))
			write(t, d, ".agents/baselines/fs.tsv", string(b)+"src/huge.ts\t5000\n")
		}, "baseline row added src/huge.ts", ".agents/baselines/fs.tsv"},
		{"config file changed", func(t *testing.T, d string) {
			write(t, d, "eslint.config.js", "export default [{ rules: { 'no-var': 'off' } }]\n")
		}, "config file changed", "eslint.config.js"},
		{"config file deleted", func(t *testing.T, d string) { os.Remove(filepath.Join(d, "eslint.config.js")) }, "config file changed", "eslint.config.js"},
		{"exception added", func(t *testing.T, d string) {
			sub(t, d, ".agents/bmax.yml", `- { path: "a/*", until: 2027-01-01 }`, `- { path: "a/*", until: 2027-01-01 }
      - { path: "b/*", until: 2026-12-01 }`)
		}, "exception added or extended b/*", ".agents/bmax.yml#lint"},
		{"exception extended", func(t *testing.T, d string) { sub(t, d, ".agents/bmax.yml", "until: 2027-01-01", "until: 2028-01-01") }, "exception added or extended a/*", ".agents/bmax.yml#lint"},
		{"hook entry removed", func(t *testing.T, d string) {
			write(t, d, ".claude/settings.json", `{"hooks":{"PreToolUse":[{"matcher":"Write|Edit|Bash","hooks":[{"type":"command","command":"sh \"$(git rev-parse --show-toplevel)/.agents/bin/bmax\" hook pre-tool-use","timeout":10}]}]}}`)
		}, "bmax hook entry removed or changed", ".claude/settings.json"},
		{"hook entry changed", func(t *testing.T, d string) { sub(t, d, ".claude/settings.json", `"timeout":120`, `"timeout":1`) }, "bmax hook entry removed or changed", ".claude/settings.json"},
		{"settings deleted", func(t *testing.T, d string) { os.Remove(filepath.Join(d, ".claude/settings.json")) }, "bmax hook entry removed or changed", ".claude/settings.json"},
		{"guide deleted", func(t *testing.T, d string) { os.Remove(filepath.Join(d, "docs/review.md")) }, "guide deleted", "docs/review.md"},
		{"guide unlisted", func(t *testing.T, d string) {
			sub(t, d, ".agents/bmax.yml", "guides: [AGENTS.md, docs/review.md]", "guides: [AGENTS.md]")
		}, "guide removed from guides", "docs/review.md"},
		{"accepted ADR edited", func(t *testing.T, d string) { sub(t, d, "docs/adr/0001-lint.md", "We lint.", "We do not lint.") }, "accepted ADR edited", "docs/adr/0001-lint.md"},
		{"accepted ADR (front matter) edited", func(t *testing.T, d string) {
			sub(t, d, "docs/adr/0002-fs.md", "# 2. File size", "# 2. File size is free")
		}, "accepted ADR edited", "docs/adr/0002-fs.md"},
		{"accepted ADR deleted", func(t *testing.T, d string) { os.Remove(filepath.Join(d, "docs/adr/0001-lint.md")) }, "accepted ADR deleted", "docs/adr/0001-lint.md"},
		{"accepted ADR status changed to rejected", func(t *testing.T, d string) {
			sub(t, d, "docs/adr/0001-lint.md", "Status: accepted", "Status: rejected")
		}, "accepted ADR edited", "docs/adr/0001-lint.md"},
		{"tsconfig strict lowered", func(t *testing.T, d string) {
			write(t, d, "tsconfig.json", "{ \"compilerOptions\": { \"strict\": false } }\n")
		}, "type-strictness: strict true -> false", "tsconfig.json"},
		{"githooks entry removed", func(t *testing.T, d string) { sub(t, d, ".agents/bmax.yml", "pre-commit: commit, ", "") }, "githooks pre-commit removed", ".agents/bmax.yml#githooks"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			d, base := harness(t)
			c.mutate(t, d)
			v, rel := check(t, d, base)
			if len(v) == 0 {
				t.Fatalf("no loosening found (released: %s)", whats(rel))
			}
			var hit *Loosening
			for i := range v {
				if strings.Contains(v[i].What, c.what) {
					hit = &v[i]
				}
			}
			if hit == nil {
				t.Fatalf("want %q in:\n%s", c.what, whats(v))
			}
			if hit.Target != c.target {
				t.Errorf("target = %q, want %q", hit.Target, c.target)
			}
			// the same change plus an ADR naming the target is released
			write(t, d, "docs/adr/0009-loosen.md", "# 9. Loosen\n\nStatus: accepted\n\nWe change "+c.target+" because of the migration.\n")
			v2, rel2 := check(t, d, base)
			for _, l := range v2 {
				if strings.Contains(l.What, c.what) {
					t.Errorf("still a violation with an ADR naming %s:\n%s", c.target, whats(v2))
				}
			}
			found := false
			for _, l := range rel2 {
				if strings.Contains(l.What, c.what) {
					found = true
				}
			}
			if !found {
				t.Errorf("not reported as released:\n%s", whats(rel2))
			}
		})
	}
}

func TestADRNamingWholeFileReleasesNothing(t *testing.T) {
	d, base := harness(t)
	sub(t, d, ".agents/bmax.yml", "retries: 1", "retries: 3")
	write(t, d, "docs/adr/0009-x.md", "# 9\nWe edit .agents/bmax.yml.\n")
	if v, _ := check(t, d, base); len(v) != 1 {
		t.Fatalf("an ADR naming the whole bmax.yml must release nothing: %s", whats(v))
	}
	write(t, d, "docs/adr/0010-y.md", "# 10\nWe edit .agents/bmax.yml#lint-extra.\n")
	if v, _ := check(t, d, base); len(v) != 1 {
		t.Fatalf("a longer ref must not release: %s", whats(v))
	}
	write(t, d, "docs/adr/0011-z.md", "# 11\nSee `.agents/bmax.yml#lint`.\n")
	if v, _ := check(t, d, base); len(v) != 0 {
		t.Fatalf("an ADR naming the script by id releases: %s", whats(v))
	}
}

func TestBaselineLooseningReleasedByScriptRefOrFile(t *testing.T) {
	d, base := harness(t)
	sub(t, d, ".agents/baselines/lint.tsv", "a.ts\t3", "a.ts\t9")
	write(t, d, "docs/adr/0009-x.md", "We grow the baseline of .agents/bmax.yml#lint.\n")
	if v, _ := check(t, d, base); len(v) != 0 {
		t.Fatalf("script ref should release the baseline: %s", whats(v))
	}
	d, base = harness(t)
	sub(t, d, ".agents/baselines/lint.tsv", "a.ts\t3", "a.ts\t9")
	write(t, d, "docs/adr/0009-x.md", "We grow .agents/baselines/lint.tsv.\n")
	if v, _ := check(t, d, base); len(v) != 0 {
		t.Fatalf("the file should release the baseline: %s", whats(v))
	}
	d, base = harness(t)
	sub(t, d, ".agents/baselines/lint.tsv", "a.ts\t3", "a.ts\t9")
	write(t, d, "docs/adr/0009-x.md", "We grow .agents/baselines/lint.tsv.bak.\n")
	if v, _ := check(t, d, base); len(v) != 1 {
		t.Fatalf("a longer file name must not release: %s", whats(v))
	}
}

func TestShrinkPasses(t *testing.T) {
	d, base := harness(t)
	sub(t, d, ".agents/baselines/lint.tsv", "a.ts\t3", "a.ts\t1")
	sub(t, d, ".agents/baselines/lint.tsv", "b.ts\t1\n", "")
	sub(t, d, ".agents/bmax.yml", "timeout: 5m", "timeout: 1m")
	sub(t, d, ".agents/bmax.yml", "retries: 1", "retries: 0")
	sub(t, d, ".agents/bmax.yml", "ceiling: 30s }\n  commit", "ceiling: 10s }\n  commit")
	sub(t, d, ".agents/bmax.yml", "until: 2027-01-01", "until: 2026-12-01")
	write(t, d, "tsconfig.json", "{ \"compilerOptions\": { \"strict\": true, \"noUncheckedIndexedAccess\": true } }\n")
	if v, _ := check(t, d, base); len(v) != 0 {
		t.Fatalf("tightening needs no ADR: %s", whats(v))
	}
}

func TestSupersedeStatusLineOnly(t *testing.T) {
	d, base := harness(t)
	sub(t, d, "docs/adr/0001-lint.md", "Status: accepted", "Status: Superseded by 0007")
	if v, _ := check(t, d, base); len(v) != 0 {
		t.Fatalf("a supersede status change is allowed: %s", whats(v))
	}
	// front matter style
	sub(t, d, "docs/adr/0002-fs.md", "status: accepted", "status: Superseded by 0008")
	if v, _ := check(t, d, base); len(v) != 0 {
		t.Fatalf("front matter supersede: %s", whats(v))
	}
	// a supersede change that also edits the body is an edit
	sub(t, d, "docs/adr/0001-lint.md", "We lint.", "We never lint.")
	if v, _ := check(t, d, base); len(v) != 1 {
		t.Fatalf("body edit + supersede: %s", whats(v))
	}
}

func TestNonAcceptedADRMayChange(t *testing.T) {
	d, base := harness(t)
	sub(t, d, "docs/adr/0003-draft.md", "# 3. Draft", "# 3. Draft (reworded)")
	os.Remove(filepath.Join(d, "docs/adr/0003-draft.md"))
	if v, _ := check(t, d, base); len(v) != 0 {
		t.Fatalf("a proposed ADR is not immutable: %s", whats(v))
	}
}

func TestADRStatusCRLF(t *testing.T) {
	if StatusOf("# 1\r\n\r\nStatus: Accepted\r\n") != "accepted" {
		t.Error("CRLF status line")
	}
	if StatusOf("---\r\nstatus: accepted\r\n---\r\n# t\r\n") != "accepted" {
		t.Error("CRLF front matter")
	}
	if StatusOf("* Status: proposed\n") != "proposed" {
		t.Error("bullet status")
	}
	if StatusOf("# no status\n") != "" {
		t.Error("no status")
	}
	// a CRLF checkout of an unchanged accepted ADR is not an edit
	d, base := harness(t)
	b, _ := os.ReadFile(filepath.Join(d, "docs/adr/0001-lint.md"))
	write(t, d, "docs/adr/0001-lint.md", strings.ReplaceAll(string(b), "\n", "\r\n"))
	if v, _ := check(t, d, base); len(v) != 0 {
		t.Fatalf("CRLF only: %s", whats(v))
	}
}

func TestDetachedHead(t *testing.T) {
	d, base := harness(t)
	git(t, d, "checkout", "-q", "--detach")
	sub(t, d, ".agents/bmax.yml", "retries: 1", "retries: 3")
	if v, _ := check(t, d, base); len(v) != 1 {
		t.Fatalf("%s", whats(v))
	}
}

func TestTypeStrictnessFiles(t *testing.T) {
	cases := []struct {
		name, file, oldBody, newBody, what string
	}{
		{"tsconfig unset", "tsconfig.json", `{ "compilerOptions": { "strict": true } }`, `{ "compilerOptions": { "target": "es2022" } }`, "strict true -> (unset)"},
		{"tsconfig flag off under strict", "tsconfig.json", `{ "compilerOptions": { "strict": true, "noImplicitAny": true } }`, `{ "compilerOptions": { "strict": true, "noImplicitAny": false } }`, "noImplicitAny true -> false"},
		{"tsconfig non-strict family", "tsconfig.json", `{ "compilerOptions": { "noUncheckedIndexedAccess": true } }`, `{ "compilerOptions": { } }`, "noUncheckedIndexedAccess true -> (unset)"},
		{"nested tsconfig", "packages/web/tsconfig.build.json", `{ "compilerOptions": { "strict": true } }`, `{ "compilerOptions": { "strict": false } }`, "strict true -> false"},
		{"mypy ini", "mypy.ini", "[mypy]\ndisallow_untyped_defs = True\n", "[mypy]\ndisallow_untyped_defs = False\n", "mypy disallow_untyped_defs true -> false"},
		{"setup.cfg", "setup.cfg", "[mypy]\nstrict = True   # all of it\n", "[mypy]\npython_version = 3.12\n", "mypy strict true -> (unset)"},
		{"pyproject mypy", "pyproject.toml", "[tool.mypy]\nstrict = true\n", "[tool.mypy]\nstrict = false\n", "mypy strict true -> false"},
		{"pyproject pyright", "pyproject.toml", "[tool.pyright]\ntypeCheckingMode = \"strict\"\n", "[tool.pyright]\ntypeCheckingMode = \"standard\"\n", "pyright typeCheckingMode strict -> standard"},
		{"pyrightconfig", "pyrightconfig.json", `{ "typeCheckingMode": "strict" }`, `{ "typeCheckingMode": "basic" }`, "pyright typeCheckingMode strict -> basic"},
		{"pyrightconfig emptied", "pyrightconfig.json", `{ "typeCheckingMode": "strict" }`, `{ }`, "pyright typeCheckingMode strict -> standard"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			d, _ := harness(t)
			write(t, d, c.file, c.oldBody)
			git(t, d, "add", "-A")
			git(t, d, "commit", "-q", "-m", "strict")
			base := git(t, d, "rev-parse", "HEAD")
			write(t, d, c.file, c.newBody)
			v, _ := check(t, d, base)
			found := false
			for _, l := range v {
				if l.Target == c.file && strings.Contains(l.What, c.what) {
					found = true
				}
			}
			if !found {
				t.Fatalf("want %q on %s:\n%s", c.what, c.file, whats(v))
			}
			write(t, d, "docs/adr/0020.md", "We lower the strictness in "+c.file+".\n")
			v, _ = check(t, d, base)
			for _, l := range v {
				if l.Target == c.file {
					t.Errorf("ADR naming %s did not release: %s", c.file, whats(v))
				}
			}
		})
	}
}

func TestTypeStrictnessOkChanges(t *testing.T) {
	cases := []struct{ name, file, oldBody, newBody string }{
		{"dropping a flag strict implies", "tsconfig.json", `{ "compilerOptions": { "strict": true, "noImplicitAny": true } }`, `{ "compilerOptions": { "strict": true } }`},
		{"turning strict on", "tsconfig.json", `{ "compilerOptions": { "strict": false } }`, `{ "compilerOptions": { "strict": true } }`},
		{"never strict", "tsconfig.json", `{ "compilerOptions": { "target": "es5" } }`, `{ "compilerOptions": { "target": "es2020", "strict": false } }`},
		{"JSONC comments", "tsconfig.json", "{\n // strict mode\n \"compilerOptions\": { \"strict\": true, }\n}", "{\n // strict mode on\n \"compilerOptions\": { \"strict\": true, }\n}"},
		{"mypy strict False -> True", "mypy.ini", "[mypy]\nstrict = False\n", "[mypy]\nstrict = True\n"},
		{"disallow_untyped_defs dropped while strict stays", "pyproject.toml", "[tool.mypy]\nstrict = true\ndisallow_untyped_defs = true\n", "[tool.mypy]\nstrict = true\n"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			d, _ := harness(t)
			write(t, d, c.file, c.oldBody)
			git(t, d, "add", "-A")
			git(t, d, "commit", "-q", "-m", "strict")
			base := git(t, d, "rev-parse", "HEAD")
			write(t, d, c.file, c.newBody)
			if v, _ := check(t, d, base); len(v) != 0 {
				t.Fatalf("%s", whats(v))
			}
		})
	}
	// deleting a strict tsconfig
	d, _ := harness(t)
	os.Remove(filepath.Join(d, "tsconfig.json"))
	base := git(t, d, "rev-parse", "HEAD")
	v, _ := check(t, d, base)
	if len(v) != 1 || !strings.Contains(v[0].What, "file removed") {
		t.Fatalf("deleted tsconfig: %s", whats(v))
	}
}

func TestConfigDeleted(t *testing.T) {
	d, base := harness(t)
	os.Remove(filepath.Join(d, ".agents/bmax.yml"))
	v, _ := check(t, d, base)
	if len(v) != 1 || v[0].What != "config deleted" {
		t.Fatalf("%s", whats(v))
	}
}

func TestNoConfigAtBase(t *testing.T) {
	d, _ := filepath.EvalSymlinks(t.TempDir())
	git(t, d, "init", "-q", ".")
	write(t, d, "x", "1")
	git(t, d, "add", "-A")
	git(t, d, "commit", "-q", "-m", "x")
	if _, _, err := Check(d, "HEAD"); err == nil {
		t.Fatal("a base without bmax.yml is the caller's case, not a silent pass")
	}
}

// ------------------------------------------------------- validation round 1

func TestConfigEntryRemovedIsALoosening(t *testing.T) {
	for _, c := range []struct {
		name, old, new string
		wantFile       string
	}{
		{"whole list removed", "    config: [eslint.config.js]\n", "", "eslint.config.js"},
		{"one file of a list removed", "    config: [eslint.config.js]\n", "    config: []\n", "eslint.config.js"},
	} {
		t.Run(c.name, func(t *testing.T) {
			d, base := harness(t)
			sub(t, d, ".agents/bmax.yml", c.old, c.new)
			v, _ := check(t, d, base)
			var hit *Loosening
			for i := range v {
				if v[i].What == "config removed" {
					hit = &v[i]
				}
			}
			if hit == nil {
				t.Fatalf("no 'config removed' in:\n%s", whats(v))
			}
			if hit.Target != c.wantFile || hit.Alt != ".agents/bmax.yml#lint" {
				t.Errorf("target=%q alt=%q", hit.Target, hit.Alt)
			}
			// released by an ADR naming either the script or the file
			for _, named := range []string{".agents/bmax.yml#lint", c.wantFile} {
				write(t, d, "docs/adr/0010-cfg.md", "We stop protecting "+named+" because of the migration.\n")
				v2, rel := check(t, d, base)
				for _, l := range v2 {
					if l.What == "config removed" {
						t.Errorf("an ADR naming %s did not release it:\n%s", named, whats(v2))
					}
				}
				found := false
				for _, l := range rel {
					found = found || l.What == "config removed"
				}
				if !found {
					t.Errorf("not reported as released for %s", named)
				}
			}
		})
	}
}

func TestOneConfigFileOfSeveralRemoved(t *testing.T) {
	d, base := harness(t)
	sub(t, d, ".agents/bmax.yml", "    config: [eslint.config.js]\n", "    config: [eslint.config.js, tsconfig.json]\n")
	git(t, d, "add", "-A")
	git(t, d, "commit", "-q", "-m", "two config files")
	base = git(t, d, "rev-parse", "HEAD")
	sub(t, d, ".agents/bmax.yml", "config: [eslint.config.js, tsconfig.json]", "config: [eslint.config.js]")
	v, _ := check(t, d, base)
	if len(v) != 1 || v[0].What != "config removed" || v[0].Target != "tsconfig.json" {
		t.Fatalf("%s", whats(v))
	}
}

func TestConfigEntryAddedIsATightening(t *testing.T) {
	d, base := harness(t)
	sub(t, d, ".agents/bmax.yml", "    config: [eslint.config.js]\n", "    config: [eslint.config.js, tsconfig.json]\n")
	if v, _ := check(t, d, base); len(v) != 0 {
		t.Fatalf("adding a config: entry needs no ADR: %s", whats(v))
	}
}

func TestConfigRemovedWithTheScript(t *testing.T) {
	d, base := harness(t)
	// the script disappears entirely, with its gate entries and its baseline
	y := strings.Replace(baseBmax, "  lint:\n", "  lintx:\n", 1)
	write(t, d, ".agents/bmax.yml", y)
	v, _ := check(t, d, base)
	found := false
	for _, l := range v {
		found = found || (l.What == "config removed" && l.Target == "eslint.config.js")
	}
	if !found {
		t.Fatalf("a script that loses its config: by disappearing: %s", whats(v))
	}
}
