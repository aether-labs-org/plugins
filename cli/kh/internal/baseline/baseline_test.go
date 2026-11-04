package baseline

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestFormatHeaderAndOrder(t *testing.T) {
	now := time.Date(2026, 11, 4, 10, 0, 0, 0, time.UTC)
	got := Format(map[string]int{"b.ts": 2, "a.ts": 3, "z.ts": 0, "A.ts": 1}, now)
	want := "# measured_at: 2026-11-04 review_by: 2027-05-04\nA.ts\t1\na.ts\t3\nb.ts\t2\n"
	if got != want {
		t.Errorf("got %q\nwant %q", got, want)
	}
	if Format(nil, now) != "# measured_at: 2026-11-04 review_by: 2027-05-04\n" {
		t.Error("empty baseline")
	}
}

func TestReadRoundTrip(t *testing.T) {
	now := time.Date(2026, 8, 31, 0, 0, 0, 0, time.UTC)
	p := filepath.Join(t.TempDir(), "x.tsv")
	os.WriteFile(p, []byte(Format(map[string]int{"a.ts": 3, "dir/My File.ts": 1}, now)), 0o644)
	b, err := Read(p)
	if err != nil || b.MeasuredAt != "2026-08-31" || b.ReviewBy != "2027-03-03" || b.Counts["dir/My File.ts"] != 1 || b.Total() != 4 {
		t.Fatalf("%+v %v", b, err)
	}
}

func TestReadCRLF(t *testing.T) {
	text := "# measured_at: 2026-11-04 review_by: 2027-05-04\r\na.ts\t3\r\nb.ts\t1\r\n"
	b, err := Parse(text, "x.tsv")
	if err != nil || b.Counts["a.ts"] != 3 || b.Counts["b.ts"] != 1 || b.ReviewBy != "2027-05-04" {
		t.Fatalf("%+v %v", b, err)
	}
}

func TestReadMalformed(t *testing.T) {
	_, err := Parse("# measured_at: 2026-11-04 review_by: 2027-05-04\na.ts\tx\n", "x.tsv")
	if err == nil || !strings.Contains(err.Error(), "line 2") {
		t.Fatalf("err = %v", err)
	}
	if _, err := Parse("a.ts\t1\n", "x.tsv"); err == nil || !strings.Contains(err.Error(), "line 1") {
		t.Fatalf("missing header: %v", err)
	}
	if _, err := Parse("# measured_at: 2026-11-04 review_by: 2027-05-04\nno-tab\n", "x.tsv"); err == nil {
		t.Fatal("row without a tab accepted")
	}
}

func TestCompareOverAndAbsent(t *testing.T) {
	b := Baseline{Counts: map[string]int{"a.ts": 3}}
	got := Compare(map[string]int{"a.ts": 4, "b.ts": 1}, b)
	if !reflect.DeepEqual(got, []string{"a.ts 4>3", "b.ts 1>0"}) {
		t.Errorf("got %v", got)
	}
}

func TestCompareShrinkPasses(t *testing.T) {
	b := Baseline{Counts: map[string]int{"a.ts": 3, "gone.ts": 2}}
	if got := Compare(map[string]int{"a.ts": 2, "c.ts": 0}, b); len(got) != 0 {
		t.Errorf("got %v", got)
	}
}
