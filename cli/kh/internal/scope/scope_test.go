package scope

import (
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func g(t *testing.T, dir string, args ...string) string {
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

// repoWithCommit: a repository with a committed seed.txt.
func repoWithCommit(t *testing.T) string {
	t.Helper()
	d, _ := filepath.EvalSymlinks(t.TempDir())
	g(t, d, "init", "-q", ".")
	write(t, d, "seed.txt", "x\n")
	g(t, d, "add", "-A")
	g(t, d, "commit", "-q", "-m", "seed")
	return d
}

func TestStagedExcludesWorktreeOnly(t *testing.T) {
	d := repoWithCommit(t)
	write(t, d, "b.ts", "1\n")
	write(t, d, "a.ts", "1\n")
	g(t, d, "add", "a.ts", "b.ts")
	g(t, d, "commit", "-q", "-m", "two")
	write(t, d, "a.ts", "2\n")
	g(t, d, "add", "a.ts")
	write(t, d, "b.ts", "2\n") // modified, not staged
	got, err := Changed(d, Staged)
	if err != nil || !reflect.DeepEqual(got, []string{"a.ts"}) {
		t.Fatalf("got %v, %v", got, err)
	}
}

func TestWorktreeIncludesUntracked(t *testing.T) {
	d := repoWithCommit(t)
	write(t, d, "seed.txt", "changed\n")
	write(t, d, "new/untracked.go", "x\n")
	write(t, d, ".gitignore", "ignored.txt\n")
	write(t, d, "ignored.txt", "x\n")
	got, err := Changed(d, Worktree)
	want := []string{".gitignore", "new/untracked.go", "seed.txt"}
	if err != nil || !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v, %v; want %v", got, err, want)
	}
}

func TestDeletedFilesDropped(t *testing.T) {
	d := repoWithCommit(t)
	os.Remove(filepath.Join(d, "seed.txt"))
	got, err := Changed(d, Worktree)
	if err != nil || len(got) != 0 {
		t.Fatalf("got %v, %v", got, err)
	}
}

func TestBranchUsesEnvBase(t *testing.T) {
	d := repoWithCommit(t)
	base := g(t, d, "rev-parse", "HEAD")
	write(t, d, "later.txt", "x\n")
	g(t, d, "add", "-A")
	g(t, d, "commit", "-q", "-m", "later")
	t.Setenv("KEEL_GUARD_BASE", base)
	got, err := Changed(d, Branch)
	if err != nil || !reflect.DeepEqual(got, []string{"later.txt"}) {
		t.Fatalf("got %v, %v", got, err)
	}
	if b, _ := BranchBase(d); b != base {
		t.Errorf("BranchBase = %q", b)
	}
}

func TestBranchNoOriginHead(t *testing.T) {
	d := repoWithCommit(t)
	t.Setenv("KEEL_GUARD_BASE", "")
	head := g(t, d, "rev-parse", "HEAD")
	b, err := BranchBase(d)
	if err != nil || b != head {
		t.Fatalf("BranchBase = %q, %v; want HEAD sha %s", b, err, head)
	}
	write(t, d, "x.txt", "1\n")
	got, err := Changed(d, Branch)
	if err != nil || !reflect.DeepEqual(got, []string{"x.txt"}) {
		t.Fatalf("got %v, %v", got, err)
	}
}

func TestBranchMergeBaseWithOriginHead(t *testing.T) {
	d := repoWithCommit(t)
	t.Setenv("KEEL_GUARD_BASE", "")
	base := g(t, d, "rev-parse", "HEAD")
	g(t, d, "update-ref", "refs/remotes/origin/main", base)
	g(t, d, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main")
	write(t, d, "f1.txt", "1\n")
	g(t, d, "add", "-A")
	g(t, d, "commit", "-q", "-m", "f1")
	b, err := BranchBase(d)
	if err != nil || b != base {
		t.Fatalf("BranchBase = %q, %v; want %s", b, err, base)
	}
	got, _ := Changed(d, Branch)
	if !reflect.DeepEqual(got, []string{"f1.txt"}) {
		t.Fatalf("got %v", got)
	}
}

func TestUnbornHead(t *testing.T) {
	d, _ := filepath.EvalSymlinks(t.TempDir())
	g(t, d, "init", "-q", ".")
	t.Setenv("KEEL_GUARD_BASE", "")
	write(t, d, "u.txt", "1\n")
	write(t, d, "s.txt", "1\n")
	g(t, d, "add", "s.txt")
	got, err := Changed(d, Worktree)
	if err != nil || !reflect.DeepEqual(got, []string{"s.txt", "u.txt"}) {
		t.Fatalf("worktree: %v, %v", got, err)
	}
	if b, err := BranchBase(d); b != "" || err != nil {
		t.Fatalf("BranchBase = %q, %v", b, err)
	}
	if got, err := Changed(d, Branch); err != nil || len(got) != 2 {
		t.Fatalf("branch: %v, %v", got, err)
	}
	if got, err := Changed(d, Staged); err != nil || !reflect.DeepEqual(got, []string{"s.txt"}) {
		t.Fatalf("staged: %v, %v", got, err)
	}
}

func TestDetachedHead(t *testing.T) {
	d := repoWithCommit(t)
	t.Setenv("KEEL_GUARD_BASE", "")
	g(t, d, "checkout", "-q", "--detach")
	write(t, d, "d.txt", "1\n")
	for _, b := range []Base{Worktree, Branch} {
		got, err := Changed(d, b)
		if err != nil || !reflect.DeepEqual(got, []string{"d.txt"}) {
			t.Fatalf("%s: %v, %v", b, got, err)
		}
	}
}

func TestOddFileNames(t *testing.T) {
	d := repoWithCommit(t)
	write(t, d, "src/My File.ts", "1\n")
	write(t, d, "src/-rf.ts", "1\n")
	write(t, d, "src/ação.ts", "1\n")
	got, err := Changed(d, Worktree)
	want := []string{"src/-rf.ts", "src/My File.ts", "src/ação.ts"}
	if err != nil || !reflect.DeepEqual(got, want) {
		t.Fatalf("got %q, %v", got, err)
	}
}

func TestTracked(t *testing.T) {
	d := repoWithCommit(t)
	write(t, d, "untracked.txt", "1\n")
	got, err := Tracked(d)
	if err != nil || !reflect.DeepEqual(got, []string{"seed.txt"}) {
		t.Fatalf("got %v, %v", got, err)
	}
}

func TestMatchBasenameAnyDepth(t *testing.T) {
	files := []string{"src/x/a.tsx", "b.ts", "a.js", "deep/er/c.ts"}
	got := Match("*.{ts,tsx}", files)
	if !reflect.DeepEqual(got, []string{"src/x/a.tsx", "b.ts", "deep/er/c.ts"}) {
		t.Fatalf("got %v", got)
	}
}

func TestMatchPathGlob(t *testing.T) {
	files := []string{"src/a.py", "src/pkg/b.py", "test/c.py", "src/d.txt", "x/src/e.py"}
	got := Match("src/**/*.py", files)
	if !reflect.DeepEqual(got, []string{"src/a.py", "src/pkg/b.py"}) {
		t.Fatalf("got %v", got)
	}
}

func TestMatchOddNames(t *testing.T) {
	files := []string{"src/My File.ts", "src/-rf.ts", "src/other.ts"}
	if got := Match("src/*.ts", files); len(got) != 3 {
		t.Fatalf("path glob: %v", got)
	}
	if got := Match("My File.ts", files); !reflect.DeepEqual(got, []string{"src/My File.ts"}) {
		t.Fatalf("space: %v", got)
	}
	if got := Match("-rf.ts", files); !reflect.DeepEqual(got, []string{"src/-rf.ts"}) {
		t.Fatalf("dash: %v", got)
	}
}

func TestBatchesUnderLimit(t *testing.T) {
	var files []string
	for i := 0; i < 10; i++ {
		files = append(files, strings.Repeat(string(rune('a'+i)), 9))
	}
	bs := Batches(files, 10, 50)
	if len(bs) != 3 {
		t.Fatalf("%d batches: %v", len(bs), bs)
	}
	var flat []string
	for _, b := range bs {
		size := 10
		for _, f := range b {
			size += len(f) + 1
		}
		if size > 50 {
			t.Errorf("batch over limit: %d", size)
		}
		flat = append(flat, b...)
	}
	if !reflect.DeepEqual(flat, files) {
		t.Errorf("order lost: %v", flat)
	}
	if got := Batches([]string{strings.Repeat("x", 100)}, 10, 50); len(got) != 1 {
		t.Errorf("oversized single file: %v", got)
	}
	if got := Batches(nil, 10, 50); len(got) != 0 {
		t.Errorf("empty: %v", got)
	}
}
