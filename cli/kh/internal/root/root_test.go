package root_test

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/aether-labs-org/plugins/cli/kh/internal/root"
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
	if err := os.WriteFile(filepath.Join(dir, ".agents", "keel.yml"), nil, 0o644); err != nil {
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
	if !strings.Contains(err.Error(), "nested .agents/keel.yml at pkg - one harness per git repository") {
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
