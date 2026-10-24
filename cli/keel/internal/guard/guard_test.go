package guard

import "testing"

func TestAwkNum(t *testing.T) {
	for in, want := range map[string]float64{"20": 20, "20\r": 20, " 7": 7, "3abc": 3, "": 0, "x": 0, "1.5": 1.5, "+4": 4, "-2": -2} {
		if got := awkNum(in); got != want {
			t.Errorf("awkNum(%q) = %v, want %v", in, got, want)
		}
	}
}

func TestCountLinesIgnoresBlankLines(t *testing.T) {
	if got := countLines("a\n  \n\tb\n"); got != 2 {
		t.Errorf("countLines = %d, want 2", got)
	}
}
