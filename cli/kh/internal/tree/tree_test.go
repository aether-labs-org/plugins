package tree_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/aether-labs-org/plugins/cli/kh/internal/tree"
)

func git(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false"}, args...)...)
	cmd.Dir = dir
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
}

func write(t *testing.T, dir, name, content string) {
	t.Helper()
	p := filepath.Join(dir, name)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func repo(t *testing.T) string {
	t.Helper()
	d, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	git(t, d, "init", "-q", ".")
	write(t, d, "a.txt", "one\n")
	git(t, d, "add", "a.txt")
	git(t, d, "commit", "-q", "-m", "seed")
	return d
}

func TestFingerprintStable(t *testing.T) {
	d := repo(t)
	a, b := tree.Fingerprint(d), tree.Fingerprint(d)
	if a != b || a.Head == "" || a.DiffHash == "" {
		t.Fatalf("%+v vs %+v", a, b)
	}
}

func TestFingerprintTrackedEdit(t *testing.T) {
	d := repo(t)
	before := tree.Fingerprint(d)
	write(t, d, "a.txt", "two\n")
	after := tree.Fingerprint(d)
	if after.DiffHash == before.DiffHash || after.Head != before.Head {
		t.Fatalf("%+v -> %+v", before, after)
	}
}

func TestFingerprintUntracked(t *testing.T) {
	d := repo(t)
	before := tree.Fingerprint(d)
	write(t, d, "new.txt", "x\n")
	mid := tree.Fingerprint(d)
	write(t, d, "new.txt", "y\n")
	after := tree.Fingerprint(d)
	if mid.DiffHash == before.DiffHash {
		t.Fatal("untracked file did not change the hash")
	}
	if after.DiffHash == mid.DiffHash {
		t.Fatal("untracked file content change did not change the hash")
	}
}

func TestFingerprintIgnoresRunDir(t *testing.T) {
	d := repo(t)
	before := tree.Fingerprint(d)
	write(t, d, ".agents/run/runs/x/output.log", "hello\n")
	after := tree.Fingerprint(d)
	if after != before {
		t.Fatalf("%+v -> %+v", before, after)
	}
}

func TestFingerprintNoGit(t *testing.T) {
	d := t.TempDir()
	write(t, d, "f", "x")
	if got := tree.Fingerprint(d); got.Head != "" || got.DiffHash != "" {
		t.Fatalf("%+v", got)
	}
}

func TestFingerprintNoCommit(t *testing.T) {
	d, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	git(t, d, "init", "-q", ".")
	write(t, d, "a.txt", "one\n")
	git(t, d, "add", "a.txt")
	got := tree.Fingerprint(d)
	if got.Head != "" || got.DiffHash == "" {
		t.Fatalf("%+v", got)
	}
}
