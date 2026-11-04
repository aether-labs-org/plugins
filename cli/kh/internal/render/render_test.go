package render_test

import (
	"strings"
	"testing"
	"unicode/utf8"

	"github.com/aether-labs-org/plugins/cli/kh/internal/reduce"
	"github.com/aether-labs-org/plugins/cli/kh/internal/render"
	"github.com/aether-labs-org/plugins/cli/kh/internal/result"
)

const id = "20261103-142233-7f3a"

func ip(n int) *int { return &n }

func lines(s string) []string { return strings.Split(strings.TrimRight(s, "\n"), "\n") }

func base(status result.Status, code *int, summary string) result.Result {
	return result.Result{
		ID: id, Command: "/usr/bin/make test", Status: status, ExitCode: code,
		DurationMS: 4250, Summary: summary,
	}
}

func TestDuration(t *testing.T) {
	for in, want := range map[int64]string{0: "0ms", 12: "12ms", 999: "999ms", 1000: "1.0s", 4250: "4.2s", 61999: "61.9s"} {
		if got := render.Duration(in); got != want {
			t.Errorf("Duration(%d) = %q, want %q", in, got, want)
		}
	}
}

func TestRenderPass(t *testing.T) {
	out := render.Run(base(result.Pass, ip(0), "completed"), reduce.Reduction{})
	got := lines(out)
	if len(got) != 2 {
		t.Fatalf("lines = %q", got)
	}
	want := "make  PASS  exit=0  4.2s  completed  [run " + id + "]"
	if got[0] != want {
		t.Fatalf("header = %q, want %q", got[0], want)
	}
	if got[1] != "evidence: kh show "+id+" [--failures | --full]" {
		t.Fatalf("evidence line = %q", got[1])
	}
	if !strings.HasSuffix(out, "\n") {
		t.Fatal("no trailing newline")
	}
}

func TestRenderPassIgnoresReduction(t *testing.T) {
	red := reduce.Reduction{Matches: []reduce.Line{{N: 1, Text: "error"}}, Tail: []reduce.Line{{N: 2, Text: "t"}}}
	if got := lines(render.Run(base(result.Pass, ip(0), "completed"), red)); len(got) != 2 {
		t.Fatalf("lines = %q", got)
	}
}

func TestRenderScriptName(t *testing.T) {
	res := base(result.Pass, ip(0), "completed")
	res.Script = "lint"
	if h := lines(render.Run(res, reduce.Reduction{}))[0]; !strings.HasPrefix(h, "lint  PASS  ") {
		t.Fatalf("header = %q", h)
	}
}

func TestRenderFail(t *testing.T) {
	red := reduce.Reduction{
		Matches: []reduce.Line{{N: 3, Text: "error: a"}, {N: 9, Text: "FAILED b"}},
		Tail:    []reduce.Line{{N: 10, Text: "t1"}, {N: 11, Text: "t2"}, {N: 12, Text: "t3"}},
	}
	got := lines(render.Run(base(result.Fail, ip(1), "exited 1"), red))
	want := []string{
		"make  FAIL  exit=1  4.2s  exited 1  [run " + id + "]",
		"  error: a",
		"  FAILED b",
		"  --- last 3 lines ---",
		"  t1",
		"  t2",
		"  t3",
		"evidence: kh show " + id + " [--failures | --full]",
	}
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Fatalf("got:\n%s\nwant:\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
}

func TestRenderFailNoTail(t *testing.T) {
	red := reduce.Reduction{Matches: []reduce.Line{{N: 1, Text: "error"}}}
	got := lines(render.Run(base(result.Fail, ip(1), "exited 1"), red))
	if len(got) != 3 || strings.Contains(strings.Join(got, "\n"), "--- last") {
		t.Fatalf("lines = %q", got)
	}
}

func TestRenderNullExit(t *testing.T) {
	res := base(result.Error, nil, "timed out after 10m0s")
	h := lines(render.Run(res, reduce.Reduction{}))[0]
	if !strings.Contains(h, "ERROR  exit=-  ") || !strings.Contains(h, "timed out after 10m0s") {
		t.Fatalf("header = %q", h)
	}
}

func TestRenderCutsLongLines(t *testing.T) {
	long := strings.Repeat("é", 5000)
	red := reduce.Reduction{Matches: []reduce.Line{{N: 1, Text: long}}}
	got := lines(render.Run(base(result.Fail, ip(1), "exited 1"), red))
	body := strings.TrimPrefix(got[1], "  ")
	if utf8.RuneCountInString(body) != render.MaxLineRunes+1 || !strings.HasSuffix(body, "…") {
		t.Fatalf("runes = %d", utf8.RuneCountInString(body))
	}
	exact := strings.Repeat("a", render.MaxLineRunes)
	red = reduce.Reduction{Matches: []reduce.Line{{N: 1, Text: exact}}}
	got = lines(render.Run(base(result.Fail, ip(1), "exited 1"), red))
	if got[1] != "  "+exact {
		t.Fatal("a line of exactly MaxLineRunes must not be cut")
	}
}

func TestRenderSanitizesBytes(t *testing.T) {
	// The CR comes first: everything before a carriage return is overwritten text.
	raw := "progress\rbad \xff byte \x1b[31mred\x1b[0m tab\there \x00nul\x7f"
	red := reduce.Reduction{Matches: []reduce.Line{{N: 1, Text: raw}}}
	out := render.Run(base(result.Fail, ip(1), "exited 1"), red)
	if !utf8.ValidString(out) {
		t.Fatal("output is not valid UTF-8")
	}
	for _, r := range out {
		if r != '\n' && r != '\t' && (r < 0x20 || (r >= 0x7f && r < 0xa0)) {
			t.Fatalf("control character %U in output", r)
		}
	}
	if !strings.ContainsRune(out, '�') {
		t.Fatal("no U+FFFD for the invalid byte")
	}
	if !strings.Contains(out, "tab\there") {
		t.Fatal("tab was removed")
	}
}

func TestRenderStripsANSIAndProgress(t *testing.T) {
	cases := map[string]string{
		"\x1b[31mred\x1b[0m done":              "red done",     // CSI colour codes vanish whole
		"\x1b]8;;http://x\x07link\x1b]8;;\x07": "link",         // OSC hyperlink
		"10%\r50%\r100% built":                 "100% built",   // progress bar: last segment wins
		"windows line\r":                       "windows line", // CRLF: trailing CR only
		"\x1b[2K\r\x1b[1mBUILD FAILED\x1b[0m":  "BUILD FAILED", // gradle-style clear + bold
	}
	for raw, want := range cases {
		red := reduce.Reduction{Matches: []reduce.Line{{N: 1, Text: raw}}}
		out := lines(render.Run(base(result.Fail, ip(1), "exited 1"), red))
		if len(out) < 2 || out[1] != "  "+want {
			t.Errorf("%q: got %q, want %q", raw, out[1], "  "+want)
		}
	}
}

func TestFailures(t *testing.T) {
	ctx := []reduce.Line{{N: 3, Text: "a"}, {N: 4, Text: "b"}, {N: 9, Text: "c"}}
	got := lines(render.Failures(base(result.Fail, ip(1), "exited 1"), ctx))
	want := []string{
		"make  FAIL  exit=1  4.2s  exited 1  [run " + id + "]",
		"3: a",
		"4: b",
		"--",
		"9: c",
	}
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Fatalf("got:\n%s", strings.Join(got, "\n"))
	}
}
