package builtin

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/aether-labs-org/plugins/cli/kh/internal/config"
	"github.com/aether-labs-org/plugins/cli/kh/internal/scope"
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

func newRepo(t *testing.T) string {
	t.Helper()
	d, _ := filepath.EvalSymlinks(t.TempDir())
	git(t, d, "init", "-q", ".")
	t.Setenv("KEEL_GUARD_BASE", "")
	return d
}

func commit(t *testing.T, d string) {
	t.Helper()
	git(t, d, "add", "-A")
	git(t, d, "commit", "-q", "-m", "c")
}

func lines(n int) string { return strings.Repeat("x\n", n) }

// ctxAll is a context over every candidate file.
func ctxAll(t *testing.T, d string) Context {
	t.Helper()
	files, err := scope.Candidates(d)
	if err != nil {
		t.Fatal(err)
	}
	base, _ := scope.BranchBase(d)
	return Context{Root: d, Files: files, All: true, Base: base, Cfg: &config.Config{ADRDir: "docs/adr"}}
}

func decode(t *testing.T, name string, with map[string]any) any {
	t.Helper()
	b := Default()[name]
	p, problems := b.Decode(with)
	if len(problems) > 0 {
		t.Fatalf("%s decode: %v", name, problems)
	}
	return p
}

func run(t *testing.T, name string, ctx Context, with map[string]any) Outcome {
	t.Helper()
	return Default()[name].Run(ctx, decode(t, name, with))
}

func TestDecodeUnknownKey(t *testing.T) {
	for _, name := range []string{"file-size", "code-language", "folder-layout", "pattern", "architecture-grep", "test-presence", "dependencies"} {
		_, problems := Default()[name].Decode(map[string]any{"limt": 3})
		if len(problems) != 1 || problems[0] != `unknown key "limt"` {
			t.Errorf("%s: problems = %v", name, problems)
		}
	}
}

func TestValidatorKnowsBuiltins(t *testing.T) {
	v := Default().Validator()
	if known, _ := v("file-sizes", nil); known {
		t.Error("file-sizes is not a builtin")
	}
	if known, problems := v("file-size", map[string]any{"limit": 300, "include": []any{"src/**"}}); !known || len(problems) != 0 {
		t.Errorf("file-size: known=%v problems=%v", known, problems)
	}
	if _, problems := v("file-size", map[string]any{"limit": "many"}); len(problems) != 1 {
		t.Errorf("wrong type accepted: %v", problems)
	}
}

func yamlList(t *testing.T, js string) []any {
	t.Helper()
	var l []any
	if err := json.Unmarshal([]byte(js), &l); err != nil {
		t.Fatal(err)
	}
	return l
}

func TestGuardBuiltin(t *testing.T) {
	// unborn HEAD: skip, never a silent pass
	d := newRepo(t)
	write(t, d, ".agents/keel.yml", "version: 1\n")
	ctx := ctxAll(t, d)
	out := Default()["guard"].Run(ctx, nil)
	if out.Status != "skip" || out.Summary != "no base commit yet" {
		t.Fatalf("unborn: %s %q", out.Status, out.Summary)
	}
	if ClassOf(Default()["guard"]) != "security" {
		t.Error("guard is a security builtin")
	}
	// harness installed in this change
	write(t, d, "x.txt", "1\n")
	git(t, d, "add", "x.txt")
	git(t, d, "commit", "-q", "-m", "no harness yet")
	ctx = ctxAll(t, d)
	out = Default()["guard"].Run(ctx, nil)
	if out.Status != "pass" || !strings.Contains(out.Summary, "installed in this change") {
		t.Fatalf("first install: %s %q", out.Status, out.Summary)
	}
	// a loosening fails with a finding naming the target
	commit(t, d)
	write(t, d, ".agents/baselines/x.tsv", "# measured_at: 2026-11-01 review_by: 2027-05-01\nsrc/a.ts\t5\n")
	commit(t, d)
	write(t, d, ".agents/baselines/x.tsv", "# measured_at: 2026-11-01 review_by: 2027-05-01\nsrc/a.ts\t9\n")
	ctx = ctxAll(t, d)
	out = Default()["guard"].Run(ctx, nil)
	if out.Status != "fail" || len(out.Findings) != 1 || out.Findings[0].File != ".agents/baselines/x.tsv" {
		t.Fatalf("loosening: %s %q %v", out.Status, out.Summary, out.Findings)
	}
}

func TestMemoryBuiltin(t *testing.T) {
	d := newRepo(t)
	if out := run(t, "memory", ctxAll(t, d), nil); out.Status != "pass" || out.Summary != "no memory files" {
		t.Fatalf("%s %q", out.Status, out.Summary)
	}
	write(t, d, ".agents/progress.md", "- 2026-11-04 s: done — ok\n")
	if out := run(t, "memory", ctxAll(t, d), nil); out.Status != "pass" || out.Summary != "1 memory file(s) checked" {
		t.Fatalf("%s %q", out.Status, out.Summary)
	}
	write(t, d, ".agents/progress.md", "- 2026-11-04 s: done — see /home/igors/x\nnonsense\n")
	out := run(t, "memory", ctxAll(t, d), nil)
	if out.Status != "fail" || len(out.Findings) != 2 || out.Findings[0].Line != 1 || out.Findings[1].Line != 2 {
		t.Fatalf("%s %v", out.Status, out.Findings)
	}
	if ClassOf(Default()["memory"]) != "correctness" {
		t.Error("memory is correctness")
	}
}
