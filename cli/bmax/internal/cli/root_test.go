package cli_test

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/cli"
)

// The dogfood incident (round 3): the session cwd moved into another git
// repository (a nested one, or a worktree of the project). The project hook then
// resolved everything from the cwd. BMAX_ROOT pins the project; every write target
// is checked against the protected set of the repository that contains it.

func gitIn(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false"}, args...)...)
	cmd.Dir = dir
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
}

func put(t *testing.T, dir, name, body string) {
	t.Helper()
	p := filepath.Join(dir, name)
	os.MkdirAll(filepath.Dir(p), 0o755)
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

// worldBmax is minimalBmax with the guide AGENTS.md (protected in project mode).
var worldBmax = strings.Replace(minimalBmax, "version: 1\n", "version: 1\nguides: [AGENTS.md]\n", 1)

type world struct{ P, N, W, out string }

// newWorld: P is a repository with a harness, N a nested repository (git init in
// an ignored directory), W a real git worktree under P/.claude/worktrees/w, out a
// directory outside any repository. HOME is isolated.
func newWorld(t *testing.T) world {
	t.Helper()
	base, _ := filepath.EvalSymlinks(t.TempDir())
	t.Setenv("HOME", filepath.Join(base, "home"))
	t.Setenv("BMAX_ROOT", "")
	t.Setenv("BMAX_GUARD_BASE", "")
	w := world{P: filepath.Join(base, "p"), out: filepath.Join(base, "out")}
	os.MkdirAll(w.P, 0o755)
	os.MkdirAll(w.out, 0o755)
	gitIn(t, w.P, "init", "-q", ".")
	put(t, w.P, ".agents/bmax.yml", worldBmax)
	put(t, w.P, "AGENTS.md", "# a\n")
	put(t, w.P, ".gitignore", ".agents/run/\nn/\n.claude/worktrees/\n")
	gitIn(t, w.P, "add", "-A")
	gitIn(t, w.P, "commit", "-q", "-m", "seed")
	w.N = filepath.Join(w.P, "n")
	os.MkdirAll(w.N, 0o755)
	gitIn(t, w.N, "init", "-q", ".")
	w.W = filepath.Join(w.P, ".claude", "worktrees", "w")
	gitIn(t, w.P, "worktree", "add", "-q", w.W, "-b", "wt")
	return w
}

func payloadAt(tool, cwd, mode, field, val string) string {
	b, _ := json.Marshal(map[string]any{
		"hook_event_name": "PreToolUse", "tool_name": tool, "cwd": cwd, "permission_mode": mode,
		"tool_input": map[string]string{field: val},
	})
	return string(b)
}

func decision(t *testing.T, stdin string, args ...string) string {
	t.Helper()
	out, errb, rc := runWithStdin(stdin, args...)
	if rc != 0 {
		t.Fatalf("rc=%d out=%q err=%q", rc, out, errb)
	}
	if out == "" {
		return "allow"
	}
	var got map[string]any
	if err := json.Unmarshal([]byte(out), &got); err != nil {
		t.Fatalf("not json: %q", out)
	}
	return got["permissionDecision"].(string)
}

func TestHookTargetsUseTheirOwnRepository(t *testing.T) {
	w := newWorld(t)
	for _, cwd := range []string{w.N, w.W} {
		cwd := cwd
		modes := []struct {
			name string
			args []string
			env  string
		}{
			{"setup", []string{"hook", "pre-tool-use", "--setup"}, ""},
			{"project with BMAX_ROOT", []string{"hook", "pre-tool-use"}, w.P},
			{"project without BMAX_ROOT", []string{"hook", "pre-tool-use"}, ""},
		}
		for _, m := range modes {
			t.Run(filepath.Base(cwd)+"/"+m.name, func(t *testing.T) {
				t.Chdir(cwd)
				t.Setenv("BMAX_ROOT", m.env)
				if got := decision(t, payloadAt("Write", cwd, "default", "file_path", w.P+"/AGENTS.md"), m.args...); got != "ask" {
					t.Errorf("Write P/AGENTS.md: %s", got)
				}
				if got := decision(t, payloadAt("Write", cwd, "default", "file_path", w.P+"/.agents/bmax.yml"), m.args...); got != "ask" {
					t.Errorf("Write P/.agents/bmax.yml: %s", got)
				}
				if got := decision(t, payloadAt("Write", cwd, "bypassPermissions", "file_path", w.P+"/AGENTS.md"), m.args...); got != "deny" {
					t.Errorf("bypass Write P/AGENTS.md: %s", got)
				}
				if got := decision(t, payloadAt("Write", cwd, "default", "file_path", cwd+"/x"), m.args...); got != "allow" {
					t.Errorf("Write cwd/x: %s", got)
				}
				if got := decision(t, payloadAt("Bash", cwd, "default", "command", "echo x > "+w.P+"/AGENTS.md"), m.args...); got != "deny" {
					t.Errorf("Bash > P/AGENTS.md: %s", got)
				}
				if got := decision(t, payloadAt("Bash", cwd, "default", "command", "echo x > x.txt"), m.args...); got != "allow" {
					t.Errorf("Bash > x.txt: %s", got)
				}
			})
		}
	}
}

func TestHookRelativeParentTargetFromNested(t *testing.T) {
	w := newWorld(t)
	t.Chdir(w.N)
	t.Setenv("BMAX_ROOT", w.P)
	if got := decision(t, payloadAt("Bash", w.N, "default", "command", "echo x > ../AGENTS.md"), "hook", "pre-tool-use"); got != "deny" {
		t.Errorf("project: %s", got)
	}
	t.Setenv("BMAX_ROOT", "")
	if got := decision(t, payloadAt("Bash", w.N, "default", "command", "echo x > ../AGENTS.md"), "hook", "pre-tool-use", "--setup"); got != "deny" {
		t.Errorf("setup: %s", got)
	}
}

func TestHookCwdOutsideAnyRepository(t *testing.T) {
	w := newWorld(t)
	t.Chdir(w.out)
	// setup mode: no project root at all, the targets decide
	setup := []string{"hook", "pre-tool-use", "--setup"}
	if got := decision(t, payloadAt("Write", w.out, "default", "file_path", w.P+"/.agents/bmax.yml"), setup...); got != "ask" {
		t.Errorf("setup Write P/.agents/bmax.yml: %s", got)
	}
	if got := decision(t, payloadAt("Write", w.out, "default", "file_path", w.out+"/x"), setup...); got != "allow" {
		t.Errorf("setup Write out/x: %s", got)
	}
	// project mode with BMAX_ROOT
	t.Setenv("BMAX_ROOT", w.P)
	proj := []string{"hook", "pre-tool-use"}
	if got := decision(t, payloadAt("Write", w.out, "default", "file_path", w.P+"/.agents/bmax.yml"), proj...); got != "ask" {
		t.Errorf("project Write P/.agents/bmax.yml: %s", got)
	}
	if got := decision(t, payloadAt("Write", w.out, "default", "file_path", w.out+"/x"), proj...); got != "allow" {
		t.Errorf("project Write out/x: %s", got)
	}
	// user-level settings stay protected outside any repository
	home := os.Getenv("HOME")
	if got := decision(t, payloadAt("Write", w.out, "default", "file_path", home+"/.claude/settings.json"), proj...); got != "ask" {
		t.Errorf("user-level settings: %s", got)
	}
}

func TestHookTargetRepositoryWithInvalidConfigIsProtected(t *testing.T) {
	w := newWorld(t)
	put(t, w.N, ".agents/bmax.yml", "version: 1\nbogus: true\n")
	t.Chdir(w.P)
	t.Setenv("BMAX_ROOT", w.P)
	if got := decision(t, payloadAt("Write", w.P, "default", "file_path", w.N+"/src/a.go"), "hook", "pre-tool-use"); got != "ask" {
		t.Errorf("invalid bmax.yml in the target's repository: %s", got)
	}
	// the project itself is still fine
	if got := decision(t, payloadAt("Write", w.P, "default", "file_path", w.P+"/src/a.go"), "hook", "pre-tool-use"); got != "allow" {
		t.Errorf("project file: %s", got)
	}
}

func TestHookTargetRepositoryWithItsOwnHarness(t *testing.T) {
	w := newWorld(t)
	put(t, w.N, ".agents/bmax.yml", worldBmax)
	put(t, w.N, "AGENTS.md", "# n\n")
	t.Chdir(w.P)
	t.Setenv("BMAX_ROOT", w.P)
	if got := decision(t, payloadAt("Write", w.P, "default", "file_path", w.N+"/AGENTS.md"), "hook", "pre-tool-use"); got != "ask" {
		t.Errorf("N's own AGENTS.md: %s", got)
	}
	// without a harness in N, a nested repo's AGENTS.md is not protected in project mode
	os.Remove(filepath.Join(w.N, ".agents/bmax.yml"))
	if got := decision(t, payloadAt("Write", w.P, "default", "file_path", w.N+"/AGENTS.md"), "hook", "pre-tool-use"); got != "allow" {
		t.Errorf("N without harness, project mode: %s", got)
	}
	// but in setup mode the setup defaults apply to the target's repository
	t.Setenv("BMAX_ROOT", "")
	if got := decision(t, payloadAt("Write", w.P, "default", "file_path", w.N+"/AGENTS.md"), "hook", "pre-tool-use", "--setup"); got != "ask" {
		t.Errorf("N without harness, setup mode: %s", got)
	}
}

func TestHookInterceptionUsesTheCwdRepository(t *testing.T) {
	w := newWorld(t)
	put(t, w.P, ".agents/bmax.yml", strings.Replace(worldBmax, `lint: "true"`, `lint: "eslint ."`, 1))
	t.Setenv("BMAX_ROOT", w.P)
	cmd := payloadAt("Bash", w.P, "default", "command", "eslint .")
	t.Chdir(w.P)
	if got := decision(t, cmd, "hook", "pre-tool-use"); got != "deny" {
		t.Errorf("cwd in the project: %s", got)
	}
	// cwd in a repository with no harness: no interception
	t.Chdir(w.N)
	cmd = payloadAt("Bash", w.N, "default", "command", "eslint .")
	if got := decision(t, cmd, "hook", "pre-tool-use"); got != "allow" {
		t.Errorf("cwd in N: %s", got)
	}
}

func TestHookBmaxRootMustBeAGitToplevel(t *testing.T) {
	w := newWorld(t)
	t.Chdir(w.P)
	t.Setenv("BMAX_ROOT", filepath.Join(w.P, "docs"))
	os.MkdirAll(filepath.Join(w.P, "docs"), 0o755)
	out, _, rc := runWithStdin(payloadAt("Write", w.P, "default", "file_path", w.P+"/src/a.go"), "hook", "pre-tool-use")
	if rc != 0 || !strings.Contains(out, `"permissionDecision":"ask"`) || !strings.Contains(out, "BMAX_ROOT") {
		t.Fatalf("rc=%d out=%q", rc, out)
	}
	if _, errb, rc := run("validate"); rc != cli.ExitError || !strings.Contains(errb, "BMAX_ROOT") {
		t.Fatalf("validate rc=%d err=%q", rc, errb)
	}
}

func TestBmaxRootOverridesTheCwd(t *testing.T) {
	w := newWorld(t)
	t.Chdir(w.N) // a repository with no harness
	if _, errb, rc := run("validate"); rc != cli.ExitError {
		t.Fatalf("without BMAX_ROOT: rc=%d err=%q", rc, errb)
	}
	t.Setenv("BMAX_ROOT", w.P)
	if _, errb, rc := run("validate"); rc != 0 {
		t.Fatalf("with BMAX_ROOT: rc=%d err=%q", rc, errb)
	}
	out, _, rc := run("gate", "extra")
	if rc != 0 || !strings.Contains(out, "gate: extra - PASSED") {
		t.Fatalf("gate rc=%d out=%q", rc, out)
	}
	// the evidence lands in the project, not in the cwd's repository
	if _, err := os.Stat(filepath.Join(w.P, ".agents", "run")); err != nil {
		t.Errorf("no evidence in the project: %v", err)
	}
	if _, err := os.Stat(filepath.Join(w.N, ".agents")); err == nil {
		t.Errorf("evidence written into N")
	}
}

const failingFast = `version: 1
scripts:
  lint: "test ! -e FAIL"
gates:
  fast: { scripts: [guard, lint] }
  commit: { scripts: [guard, lint], changes: staged }
  slow: { scripts: [guard, lint], changes: branch }
`

func TestStopWithBmaxRootRunsTheProjectGate(t *testing.T) {
	w := newWorld(t)
	put(t, w.P, ".agents/bmax.yml", failingFast)
	put(t, w.P, "FAIL", "x")
	t.Chdir(w.N)
	t.Setenv("BMAX_ROOT", w.P)
	out, _, rc := runWithStdin(`{"hook_event_name":"Stop","cwd":"`+w.N+`"}`, "hook", "stop")
	if rc != 0 || !strings.Contains(out, `"decision":"block"`) {
		t.Fatalf("rc=%d out=%q", rc, out)
	}
	// without BMAX_ROOT the nested repository has no harness: a systemMessage, no block
	t.Setenv("BMAX_ROOT", "")
	out, _, rc = runWithStdin(`{"hook_event_name":"Stop","cwd":"`+w.N+`"}`, "hook", "stop")
	if rc != 0 || strings.Contains(out, `"block"`) || !strings.Contains(out, "systemMessage") {
		t.Fatalf("no BMAX_ROOT: rc=%d out=%q", rc, out)
	}
}

func TestFailSafeWhenTheCwdIsNotInARepositoryDoesNotBlameSetup(t *testing.T) {
	d := t.TempDir()
	t.Chdir(d)
	t.Setenv("BMAX_ROOT", "")
	out, _, rc := runWithStdin(`{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"`+d+`","tool_input":{"command":"ls"}}`, "hook", "pre-tool-use")
	if rc != 0 || !strings.Contains(out, "not in a git repository") || strings.Contains(out, "bmax setup") {
		t.Fatalf("rc=%d out=%q", rc, out)
	}
}

// ---- round 3 correction: a fake .git entry must not unprotect the harness ----
// Every enclosing repository judges a write, not only the nearest one; a real nested repository or
// worktree is still judged by its own set, and the outer root-relative patterns do not reach into it.

func fakeGit(t *testing.T, kind, dir string) {
	t.Helper()
	os.MkdirAll(dir, 0o755)
	switch kind {
	case "empty dir":
		os.MkdirAll(filepath.Join(dir, ".git"), 0o755)
	case "gitdir file":
		os.WriteFile(filepath.Join(dir, ".git"), []byte("gitdir: /nonexistent/elsewhere\n"), 0o644)
	case "git init":
		gitIn(t, dir, "init", "-q", ".")
	}
}

func TestFakeGitEntriesDoNotUnprotectTheHarness(t *testing.T) {
	for _, kind := range []string{"empty dir", "gitdir file", "git init"} {
		for _, rel := range []string{".agents/bmax.yml", ".agents/githooks/pre-commit", ".claude/settings.json", "docs/adr/0001-x.md"} {
			w := newWorld(t)
			dir := filepath.Dir(filepath.Join(w.P, rel))
			fakeGit(t, kind, dir)
			target := filepath.Join(w.P, rel)
			modes := []struct {
				name, root string
				args       []string
			}{
				{"setup", "", []string{"hook", "pre-tool-use", "--setup"}},
				{"project BMAX_ROOT", w.P, []string{"hook", "pre-tool-use"}},
				{"project no BMAX_ROOT", "", []string{"hook", "pre-tool-use"}},
			}
			for _, m := range modes {
				t.Run(kind+"/"+rel+"/"+m.name, func(t *testing.T) {
					t.Chdir(w.P)
					t.Setenv("BMAX_ROOT", m.root)
					for _, tool := range []string{"Write", "Edit"} {
						if got := decision(t, payloadAt(tool, w.P, "default", "file_path", target), m.args...); got != "ask" {
							t.Errorf("%s %s: %s", tool, rel, got)
						}
						if got := decision(t, payloadAt(tool, w.P, "bypassPermissions", "file_path", target), m.args...); got != "deny" {
							t.Errorf("bypass %s %s: %s", tool, rel, got)
						}
					}
					if got := decision(t, payloadAt("Bash", w.P, "default", "command", "echo x > "+rel), m.args...); got != "deny" {
						t.Errorf("Bash > %s: %s", rel, got)
					}
					if got := decision(t, payloadAt("Bash", w.P, "default", "command", "echo x > "+target), m.args...); got != "deny" {
						t.Errorf("Bash > abs %s: %s", rel, got)
					}
				})
			}
		}
	}
}

// a worktree that carries no harness of its own: the project's root-relative patterns do not match inside it
func TestWorktreeWithoutHarnessIsNotJudgedByTheOuterPatterns(t *testing.T) {
	w := newWorld(t)
	// a commit with an empty tree: a worktree made from it carries no harness
	tree, err := exec.Command("git", "-C", w.P, "hash-object", "-w", "-t", "tree", "/dev/null").Output()
	if err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("git", "-C", w.P, "-c", "user.email=t@t", "-c", "user.name=t", "commit-tree", strings.TrimSpace(string(tree)), "-m", "bare")
	out, err := cmd.Output()
	if err != nil {
		t.Fatal(err)
	}
	bare := strings.TrimSpace(string(out))
	w2 := filepath.Join(w.P, ".claude", "worktrees", "w2")
	gitIn(t, w.P, "worktree", "add", "-q", "--detach", w2, bare)
	if _, err := os.Stat(filepath.Join(w2, ".agents")); err == nil {
		t.Fatal("w2 has a harness")
	}
	t.Chdir(w.P)
	for _, f := range []string{"AGENTS.md", ".claude/settings.json", "docs/adr/0001.md"} {
		target := filepath.Join(w2, f)
		t.Setenv("BMAX_ROOT", w.P)
		if got := decision(t, payloadAt("Write", w.P, "default", "file_path", target), "hook", "pre-tool-use"); got != "allow" {
			t.Errorf("project mode, Write w2/%s: %s", f, got)
		}
		t.Setenv("BMAX_ROOT", "")
		if got := decision(t, payloadAt("Write", w.P, "default", "file_path", target), "hook", "pre-tool-use", "--setup"); got != "ask" {
			t.Errorf("setup mode, Write w2/%s: %s", f, got)
		}
	}
}
