package root_test

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/root"
)

func git(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false"}, args...)...)
	cmd.Dir = dir
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
}

func mark(t *testing.T, dir string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Join(dir, ".agents"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, ".agents", "bmax.yml"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
}

func tmp(t *testing.T) string {
	t.Helper()
	d, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return d
}

func gitRepo(t *testing.T) string {
	t.Helper()
	d := tmp(t)
	git(t, d, "init", "-q", ".")
	return d
}

func TestFindTopLevel(t *testing.T) {
	r := gitRepo(t)
	mark(t, r)
	sub := filepath.Join(r, "src", "a")
	if err := os.MkdirAll(sub, 0o755); err != nil {
		t.Fatal(err)
	}
	got, err := root.Find(sub)
	if err != nil || got != r {
		t.Fatalf("Find = %q, %v; want %q", got, err, r)
	}
}

func TestFindNested(t *testing.T) {
	r := gitRepo(t)
	mark(t, r)
	pkg := filepath.Join(r, "pkg")
	mark(t, pkg)
	_, err := root.Find(pkg)
	if !errors.Is(err, root.ErrNested) {
		t.Fatalf("err = %v; want ErrNested", err)
	}
	if !strings.Contains(err.Error(), "nested .agents/bmax.yml at pkg - one harness per git repository") {
		t.Errorf("message = %q", err)
	}
	// a nested file in a directory we are not inside does not matter
	if got, err := root.Find(r); err != nil || got != r {
		t.Fatalf("Find(top) = %q, %v", got, err)
	}
}

func TestFindNestedWithoutTopLevel(t *testing.T) {
	r := gitRepo(t)
	pkg := filepath.Join(r, "pkg")
	mark(t, pkg)
	if _, err := root.Find(pkg); !errors.Is(err, root.ErrNested) {
		t.Fatalf("err = %v; want ErrNested", err)
	}
}

func TestFindNotFound(t *testing.T) {
	r := gitRepo(t)
	_, err := root.Find(r)
	if !errors.Is(err, root.ErrNotFound) {
		t.Fatalf("err = %v; want ErrNotFound", err)
	}
}

func TestFindNotGit(t *testing.T) {
	d := tmp(t)
	mark(t, d)
	_, err := root.Find(d)
	if !errors.Is(err, root.ErrNotGit) {
		t.Fatalf("err = %v; want ErrNotGit", err)
	}
	if !strings.Contains(err.Error(), "not a git repository") {
		t.Errorf("message = %q", err)
	}
}

func TestFindWorktree(t *testing.T) {
	r := gitRepo(t)
	mark(t, r)
	git(t, r, "add", "-A")
	git(t, r, "commit", "-q", "-m", "seed")
	wt := filepath.Join(tmp(t), "wt")
	git(t, r, "worktree", "add", "-q", "-b", "other", wt)
	if st, err := os.Stat(filepath.Join(wt, ".git")); err != nil || st.IsDir() {
		t.Fatalf(".git of a worktree should be a file: %v", err)
	}
	sub := filepath.Join(wt, "x")
	os.MkdirAll(sub, 0o755)
	got, err := root.Find(sub)
	if err != nil || got != wt {
		t.Fatalf("Find = %q, %v; want %q", got, err, wt)
	}
}

func TestToplevel(t *testing.T) {
	r := gitRepo(t)
	got, err := root.Toplevel(r)
	if err != nil || got != r {
		t.Fatalf("Toplevel = %q, %v", got, err)
	}
	if _, err := root.Toplevel(tmp(t)); !errors.Is(err, root.ErrNotGit) {
		t.Fatalf("err = %v", err)
	}
}

func TestContainingAndEnclosing(t *testing.T) {
	p := gitRepo(t)
	n := filepath.Join(p, "n")
	os.MkdirAll(n, 0o755)
	git(t, n, "init", "-q", ".")
	out := tmp(t)
	cases := []struct{ path, want string }{
		{filepath.Join(p, "AGENTS.md"), p},                   // does not exist yet
		{filepath.Join(p, "deep", "er", "x"), p},             // no existing ancestor but the repo
		{filepath.Join(p, ".git", "hooks", "pre-commit"), p}, // inside .git, where git rev-parse refuses
		{filepath.Join(p, ".git", "config"), p},              // an existing file inside .git
		{filepath.Join(n, "x"), n},                           // nested repository
		{n, n},                                               // the nested top-level itself
		{filepath.Join(out, "x"), ""},                        // outside any repository
	}
	for _, c := range cases {
		if got := root.Containing(c.path); got != c.want {
			t.Errorf("Containing(%s) = %q, want %q", c.path, got, c.want)
		}
	}
	if got := root.Enclosing(filepath.Join(n, "x")); len(got) != 2 || got[0] != n || got[1] != p {
		t.Errorf("Enclosing = %v", got)
	}
	if got := root.Enclosing(filepath.Join(out, "x")); len(got) != 0 {
		t.Errorf("Enclosing outside = %v", got)
	}
	// a symlink to a directory of another repository: the target is judged there
	os.Symlink(n, filepath.Join(p, "link"))
	if got := root.Containing(filepath.Join(p, "link", "x")); got != n {
		t.Errorf("through a symlink = %q, want %q", got, n)
	}
}

func TestContainingWorktree(t *testing.T) {
	p := gitRepo(t)
	os.WriteFile(filepath.Join(p, "a"), []byte("x"), 0o644)
	git(t, p, "add", "-A")
	git(t, p, "commit", "-q", "-m", "s")
	w := filepath.Join(p, "wt")
	git(t, p, "worktree", "add", "-q", w, "-b", "b")
	if got := root.Containing(filepath.Join(w, "a")); got != w {
		t.Errorf("worktree file = %q, want %q", got, w)
	}
	if got := root.Containing(w + "/.git"); got != w {
		t.Errorf("worktree .git file = %q, want %q", got, w)
	}
}

func TestFromEnv(t *testing.T) {
	r := gitRepo(t)
	mark(t, r)
	if got, err := root.FromEnv(r); err != nil || got != r {
		t.Fatalf("FromEnv(top) = %q, %v", got, err)
	}
	sub := filepath.Join(r, "sub")
	os.MkdirAll(sub, 0o755)
	if _, err := root.FromEnv(sub); err == nil || !strings.Contains(err.Error(), "BMAX_ROOT") {
		t.Errorf("a subdirectory is not a top-level: %v", err)
	}
	if _, err := root.FromEnv(tmp(t)); err == nil {
		t.Error("outside any repository accepted")
	}
	bare := gitRepo(t)
	if _, err := root.FromEnv(bare); !errors.Is(err, root.ErrNotFound) {
		t.Errorf("no bmax.yml: %v", err)
	}
	if got, err := root.Pinned(bare); err != nil || got != bare {
		t.Errorf("Pinned without bmax.yml: %q, %v", got, err)
	}
	link := filepath.Join(tmp(t), "link")
	os.Symlink(r, link)
	if got, err := root.FromEnv(link); err != nil || got != r {
		t.Errorf("symlinked root = %q, %v", got, err)
	}
}
