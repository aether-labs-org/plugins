package reduce_test

import (
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/reduce"
)

func logFile(t *testing.T, content string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "output.log")
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func ns(ls []reduce.Line) []int {
	var out []int
	for _, l := range ls {
		out = append(out, l.N)
	}
	return out
}

func TestReduceMatchesFirstFive(t *testing.T) {
	var b strings.Builder
	for i := 1; i <= 30; i++ {
		if i%3 == 0 && i <= 24 { // 8 matching lines: 3,6,...,24
			fmt.Fprintf(&b, "error x %d\n", i)
		} else {
			fmt.Fprintf(&b, "line %d\n", i)
		}
	}
	red, err := reduce.FromFile(logFile(t, b.String()))
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(ns(red.Matches), []int{3, 6, 9, 12, 15}) {
		t.Fatalf("matches = %v", ns(red.Matches))
	}
	if red.Total != 30 {
		t.Fatalf("Total = %d", red.Total)
	}
	if red.Matches[0].Text != "error x 3" {
		t.Fatalf("text = %q", red.Matches[0].Text)
	}
}

func TestReduceTailExcludesMatches(t *testing.T) {
	var b strings.Builder
	for i := 1; i <= 25; i++ {
		fmt.Fprintf(&b, "line %d\n", i)
	}
	b.WriteString("FAILED at the end\n") // line 26
	red, err := reduce.FromFile(logFile(t, b.String()))
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(ns(red.Matches), []int{26}) {
		t.Fatalf("matches = %v", ns(red.Matches))
	}
	want := []int{16, 17, 18, 19, 20, 21, 22, 23, 24, 25}
	if !reflect.DeepEqual(ns(red.Tail), want) {
		t.Fatalf("tail = %v, want %v", ns(red.Tail), want)
	}
}

func TestReduceShortLog(t *testing.T) {
	red, err := reduce.FromFile(logFile(t, "a\nb\nc"))
	if err != nil {
		t.Fatal(err)
	}
	if len(red.Matches) != 0 || !reflect.DeepEqual(ns(red.Tail), []int{1, 2, 3}) || red.Total != 3 {
		t.Fatalf("%+v", red)
	}
	if red.Tail[2].Text != "c" {
		t.Fatalf("last line = %q", red.Tail[2].Text)
	}
}

func TestReduceWordBoundary(t *testing.T) {
	log := "terrors here\nerrorless\nError: boom\nFAILED\nnothing\nthe panic\nTraceback (most recent call last)\n"
	red, err := reduce.FromFile(logFile(t, log))
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(ns(red.Matches), []int{3, 4, 6, 7}) {
		t.Fatalf("matches = %v", ns(red.Matches))
	}
}

func TestReduceEmptyLog(t *testing.T) {
	red, err := reduce.FromFile(logFile(t, ""))
	if err != nil {
		t.Fatal(err)
	}
	if len(red.Matches) != 0 || len(red.Tail) != 0 || red.Total != 0 {
		t.Fatalf("%+v", red)
	}
}

func TestReduceHugeLine(t *testing.T) {
	huge := strings.Repeat("x", 3<<20)
	red, err := reduce.FromFile(logFile(t, "a\n"+huge+"\nerror z\n"))
	if err != nil {
		t.Fatal(err)
	}
	if red.Total != 3 || len(red.Tail) != 2 || red.Matches[0].N != 3 {
		t.Fatalf("total=%d tail=%d", red.Total, len(red.Tail))
	}
}

func TestContextMerges(t *testing.T) {
	var b strings.Builder
	for i := 1; i <= 20; i++ {
		fmt.Fprintf(&b, "l%d\n", i)
	}
	ctx, err := reduce.Context(logFile(t, b.String()), []reduce.Line{{N: 5}, {N: 7}}, 2)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(ns(ctx), []int{3, 4, 5, 6, 7, 8, 9}) {
		t.Fatalf("ctx = %v", ns(ctx))
	}
	if ctx[0].Text != "l3" {
		t.Fatalf("text = %q", ctx[0].Text)
	}
}

func TestContextClampsAndSeparates(t *testing.T) {
	var b strings.Builder
	for i := 1; i <= 20; i++ {
		fmt.Fprintf(&b, "l%d\n", i)
	}
	ctx, err := reduce.Context(logFile(t, b.String()), []reduce.Line{{N: 1}, {N: 20}}, 1)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(ns(ctx), []int{1, 2, 19, 20}) {
		t.Fatalf("ctx = %v", ns(ctx))
	}
}
