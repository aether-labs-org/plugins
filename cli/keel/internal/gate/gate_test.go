package gate

import "testing"

func TestCutFieldMimicsCut(t *testing.T) {
	cases := []struct {
		line string
		n    int
		want string
	}{
		{"a\tb\tc\td", 2, "b"}, {"a\tb\tc\td", 4, "d"}, {"a\tb", 4, ""}, {"no tabs here", 2, "no tabs here"}, {"", 2, ""},
	}
	for _, c := range cases {
		if got := cutField(c.line, c.n); got != c.want {
			t.Errorf("cutField(%q, %d) = %q, want %q", c.line, c.n, got, c.want)
		}
	}
}

func TestPaddingCountsBytesLikeBashPrintf(t *testing.T) {
	if got := padRight("ação", 12); got != "ação      " || len(got) != 12 {
		t.Errorf("padRight = %q (%d bytes), want 12 bytes", got, len(got))
	}
	if got := padLeft("12ms", 8); got != "    12ms" {
		t.Errorf("padLeft = %q", got)
	}
	if got := padRight("longer than twelve", 12); got != "longer than twelve" {
		t.Errorf("padRight must not truncate, got %q", got)
	}
}

func TestDuration(t *testing.T) {
	for ms, want := range map[int64]string{0: "0ms", 999: "999ms", 1000: "1.0s", 1234: "1.2s", 61999: "61.9s"} {
		if got := duration(ms); got != want {
			t.Errorf("duration(%d) = %q, want %q", ms, got, want)
		}
	}
}

func TestRunStateIsExcludedFromScope(t *testing.T) {
	for p, excluded := range map[string]bool{
		".agents/last-run.log": true, ".agents/last-seen": true, ".agents/.gate-lock/x": true,
		".agents/notes.md": false, ".agents/keel.yaml": false, "src/last-run.log": false,
	} {
		if got := runState.MatchString(p); got != excluded {
			t.Errorf("runState(%q) = %v, want %v", p, got, excluded)
		}
	}
}
