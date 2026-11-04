// Package render turns a Result and a Reduction into the agent-facing text.
package render

import (
	"fmt"
	"path"
	"regexp"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/aether-labs-org/plugins/cli/kh/internal/reduce"
	"github.com/aether-labs-org/plugins/cli/kh/internal/result"
)

// MaxLineRunes is the longest log line printed; longer lines are cut with "…".
const MaxLineRunes = 300

// Duration formats milliseconds as "NNNms" below one second, else "S.Ds"
// (one decimal, truncated).
func Duration(ms int64) string {
	if ms < 1000 {
		return fmt.Sprintf("%dms", ms)
	}
	return fmt.Sprintf("%d.%ds", ms/1000, (ms%1000)/100)
}

func name(res result.Result) string {
	if res.Script != "" {
		return res.Script
	}
	first, _, _ := strings.Cut(res.Command, " ")
	return path.Base(first)
}

func header(res result.Result) string {
	code := "-"
	if res.ExitCode != nil {
		code = fmt.Sprint(*res.ExitCode)
	}
	return fmt.Sprintf("%s  %s  exit=%s  %s  %s  [run %s]",
		name(res), strings.ToUpper(string(res.Status)), code, Duration(res.DurationMS), res.Summary, res.ID)
}

// ansi matches terminal escape sequences: CSI (colours, cursor moves), OSC
// (titles, hyperlinks; ended by BEL or ESC \) and the two-byte escapes.
var ansi = regexp.MustCompile(`\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[@-Z\\-_]`)

// clean makes a log line safe to print: terminal escape sequences are removed,
// a carriage return keeps only what was written after it (progress bars; a
// trailing CR of CRLF is just dropped), invalid UTF-8 becomes U+FFFD (per
// byte), control characters other than tab are dropped, and the line is cut to
// MaxLineRunes runes plus "…".
func clean(s string) string {
	s = ansi.ReplaceAllString(s, "")
	s = strings.TrimRight(s, "\r")
	if i := strings.LastIndexByte(s, '\r'); i >= 0 {
		s = s[i+1:]
	}
	var b strings.Builder
	runes := 0
	for i := 0; i < len(s); {
		r, size := utf8.DecodeRuneInString(s[i:])
		i += size
		if r == utf8.RuneError && size == 1 {
			r = unicode.ReplacementChar
		} else if r != '\t' && unicode.IsControl(r) {
			continue
		}
		if runes == MaxLineRunes {
			b.WriteString("…")
			return b.String()
		}
		b.WriteRune(r)
		runes++
	}
	return b.String()
}

// Run renders the compact text of a run.
func Run(res result.Result, red reduce.Reduction) string {
	var b strings.Builder
	b.WriteString(header(res) + "\n")
	if res.Status != result.Pass {
		for _, l := range red.Matches {
			b.WriteString("  " + clean(l.Text) + "\n")
		}
		if len(red.Tail) > 0 {
			fmt.Fprintf(&b, "  --- last %d lines ---\n", len(red.Tail))
			for _, l := range red.Tail {
				b.WriteString("  " + clean(l.Text) + "\n")
			}
		}
	}
	fmt.Fprintf(&b, "evidence: kh show %s [--failures | --full]\n", res.ID)
	return b.String()
}

// Failures renders the header and the given context lines as "<N>: <text>",
// with "--" between non-adjacent groups.
func Failures(res result.Result, ctx []reduce.Line) string {
	var b strings.Builder
	b.WriteString(header(res) + "\n")
	prev := 0
	for _, l := range ctx {
		if prev != 0 && l.N != prev+1 {
			b.WriteString("--\n")
		}
		fmt.Fprintf(&b, "%d: %s\n", l.N, clean(l.Text))
		prev = l.N
	}
	return b.String()
}
