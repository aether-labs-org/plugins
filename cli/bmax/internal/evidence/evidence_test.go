package evidence

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"testing"
	"time"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/result"
)

func tmp(t *testing.T) string {
	t.Helper()
	d, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return d
}

func mkRun(t *testing.T, root, id string, size int) {
	t.Helper()
	d := filepath.Join(runsDir(root), id)
	if err := os.MkdirAll(d, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(d, "output.log"), make([]byte, size), 0o644); err != nil {
		t.Fatal(err)
	}
}

func names(t *testing.T, root string) []string {
	t.Helper()
	es, err := os.ReadDir(runsDir(root))
	if err != nil {
		t.Fatal(err)
	}
	var out []string
	for _, e := range es {
		out = append(out, e.Name())
	}
	return out
}

func TestNewIDFormat(t *testing.T) {
	loc := time.FixedZone("x", -3*3600)
	now := time.Date(2026, 11, 3, 23, 5, 9, 0, loc)
	id := NewID(now, bytes.NewReader([]byte{0xab, 0x01}))
	if !regexp.MustCompile(`^\d{8}-\d{6}-[0-9a-f]{4}$`).MatchString(id) {
		t.Fatalf("id = %q", id)
	}
	if id != "20261104-020509-ab01" {
		t.Fatalf("id = %q, want UTC 20261104-020509-ab01", id)
	}
}

func TestCreateCollision(t *testing.T) {
	root := tmp(t)
	now := time.Date(2026, 11, 3, 12, 0, 0, 0, time.UTC)
	old := randReader
	defer func() { randReader = old }()
	randReader = bytes.NewReader([]byte{0x00, 0x01, 0x00, 0x02})
	first := NewID(now, bytes.NewReader([]byte{0x00, 0x01}))
	if err := os.MkdirAll(filepath.Join(runsDir(root), first), 0o755); err != nil {
		t.Fatal(err)
	}
	r, err := Create(root, now)
	if err != nil {
		t.Fatal(err)
	}
	if r.ID == first || r.ID != "20261103-120000-0002" {
		t.Fatalf("ID = %q (first %q)", r.ID, first)
	}
	if r.Root != root || r.Dir != filepath.Join(runsDir(root), r.ID) {
		t.Fatalf("%+v", r)
	}
	if st, err := os.Stat(r.Dir); err != nil || !st.IsDir() {
		t.Fatal("dir not created")
	}
	if r.LogPath() != filepath.Join(r.Dir, "output.log") {
		t.Fatalf("LogPath = %q", r.LogPath())
	}
}

func sample() result.Result {
	return result.Result{
		ID: "20261103-120000-0002", Command: "true", Status: result.Pass, ExitCode: new(int),
		Attempts: 1, DurationMS: 12, Summary: "completed",
		Findings:    []result.Finding{},
		Evidence:    result.Evidence{Dir: ".agents/run/runs/x", Log: ".agents/run/runs/x/output.log", Reports: []string{}},
		Tree:        result.Tree{Head: "abc", DiffHash: "def"},
		BmaxVersion: "0.4.0-dev", Cwd: "/r", TimeoutMS: 600000,
		StartedAt:  time.Date(2026, 11, 3, 12, 0, 0, 5, time.UTC),
		FinishedAt: time.Date(2026, 11, 3, 12, 0, 1, 7, time.UTC),
	}
}

func TestLoadRoundTrip(t *testing.T) {
	root := tmp(t)
	r, err := Create(root, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	in := sample()
	in.ID = r.ID
	if err := r.WriteMeta(in); err != nil {
		t.Fatal(err)
	}
	got, err := Load(root, r.ID)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, in) {
		t.Fatalf("got  %+v\nwant %+v", got, in)
	}
	es, _ := os.ReadDir(r.Dir)
	for _, e := range es {
		if e.Name() != "meta.json" {
			t.Errorf("stray file %s after WriteMeta", e.Name())
		}
	}
}

func TestLoadUnknown(t *testing.T) {
	root := tmp(t)
	for _, id := range []string{"nope", "../x", "20000101-000000-dead", ""} {
		if _, err := Load(root, id); !errors.Is(err, ErrNoRun) {
			t.Errorf("Load(%q) err = %v", id, err)
		}
	}
}

func id(i int) string { return fmt.Sprintf("20260101-%06d-%04x", i, i) }

func TestPruneByCount(t *testing.T) {
	root := tmp(t)
	for i := 1; i <= 56; i++ {
		mkRun(t, root, id(i), 10)
	}
	current := id(56)
	if err := Prune(root, current, MaxRuns, MaxBytes); err != nil {
		t.Fatal(err)
	}
	got := names(t, root)
	if len(got) != 50 {
		t.Fatalf("%d runs remain", len(got))
	}
	if got[0] != id(7) || got[49] != current {
		t.Fatalf("remaining %s .. %s", got[0], got[49])
	}
}

func TestPruneKeepsCurrentEvenIfOldest(t *testing.T) {
	root := tmp(t)
	for i := 1; i <= 4; i++ {
		mkRun(t, root, id(i), 10)
	}
	if err := Prune(root, id(1), 2, MaxBytes); err != nil {
		t.Fatal(err)
	}
	got := names(t, root)
	if len(got) != 2 || got[0] != id(1) || got[1] != id(4) {
		t.Fatalf("remaining %v", got)
	}
}

func TestPruneBySize(t *testing.T) {
	root := tmp(t)
	for i := 1; i <= 5; i++ {
		mkRun(t, root, id(i), 1<<20)
	}
	if err := Prune(root, id(5), MaxRuns, 3<<20); err != nil {
		t.Fatal(err)
	}
	got := names(t, root)
	want := []string{id(3), id(4), id(5)}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("remaining %v, want %v", got, want)
	}
}

func TestPruneIgnoresOthers(t *testing.T) {
	root := tmp(t)
	for i := 1; i <= 3; i++ {
		mkRun(t, root, id(i), 10)
	}
	if err := os.MkdirAll(filepath.Join(runsDir(root), "notes"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(runsDir(root), "x.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := Prune(root, id(3), 1, MaxBytes); err != nil {
		t.Fatal(err)
	}
	got := names(t, root)
	want := []string{id(3), "notes", "x.txt"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("remaining %v, want %v", got, want)
	}
}

func TestPruneNoRunsDir(t *testing.T) {
	if err := Prune(tmp(t), "x", MaxRuns, MaxBytes); err != nil {
		t.Fatal(err)
	}
}
