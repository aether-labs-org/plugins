package root_test

import (
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/aether-labs-org/plugins/cli/kh/internal/root"
)

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

func TestFindRootFromSubdir(t *testing.T) {
	r := tmp(t)
	mark(t, r)
	sub := filepath.Join(r, "a", "b")
	if err := os.MkdirAll(sub, 0o755); err != nil {
		t.Fatal(err)
	}
	got, err := root.Find(sub)
	if err != nil || got != r {
		t.Fatalf("Find = %q, %v; want %q", got, err, r)
	}
}

func TestFindRootNearestWins(t *testing.T) {
	r := tmp(t)
	mark(t, r)
	s := filepath.Join(r, "sub")
	mark(t, s)
	x := filepath.Join(s, "x")
	if err := os.MkdirAll(x, 0o755); err != nil {
		t.Fatal(err)
	}
	got, err := root.Find(x)
	if err != nil || got != s {
		t.Fatalf("Find = %q, %v; want %q", got, err, s)
	}
}

func TestFindRootNotFound(t *testing.T) {
	d := tmp(t)
	_, err := root.Find(d)
	if !errors.Is(err, root.ErrNotFound) {
		t.Fatalf("err = %v; want ErrNotFound", err)
	}
}
