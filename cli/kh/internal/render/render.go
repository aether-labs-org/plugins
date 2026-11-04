// Package render turns a Result and a Reduction into the agent-facing text.
package render

import (
	"fmt"
	"path"
	"regexp"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/aether-labs-org/plugins/cli/kh/internal/gate"
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

// MaxFindings is the most findings printed for one script.
const MaxFindings = 5

// findingLine renders "file:line  rule  message", leaving out what is empty.
func findingLine(f result.Finding) string {
	loc := f.File
	if loc != "" && f.Line > 0 {
		loc = fmt.Sprintf("%s:%d", loc, f.Line)
	}
	var parts []string
	for _, p := range []string{loc, f.Rule, f.Message} {
		if p != "" {
			parts = append(parts, clean(p))
		}
	}
	return strings.Join(parts, "  ")
}

// Run renders the compact text of a run: the header, for a script that did not
// pass at most MaxFindings findings (most severe first) or else the generic
// reduction, the guidance, and where the evidence is.
func Run(res result.Result, red reduce.Reduction) string {
	var b strings.Builder
	b.WriteString(header(res) + "\n")
	if res.Status != result.Pass {
		switch {
		case res.Baseline != nil && len(res.Baseline.Over) > 0:
			over := res.Baseline.Over
			more := ""
			if len(over) > MaxFindings {
				more = fmt.Sprintf(" (+%d more)", len(over)-MaxFindings)
				over = over[:MaxFindings]
			}
			fmt.Fprintf(&b, "  over baseline %s: %s%s\n", res.Baseline.File, strings.Join(over, ", "), more)
			fallthrough
		case len(res.Findings) > 0:
			for i, f := range res.Findings {
				if i == MaxFindings {
					fmt.Fprintf(&b, "  … and %d more\n", len(res.Findings)-MaxFindings)
					break
				}
				b.WriteString("  " + findingLine(f) + "\n")
			}
		default:
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
		if res.Guidance != "" && res.Status == result.Fail {
			b.WriteString("  guidance: " + clean(res.Guidance) + "\n")
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

// MaxGateLines caps the text of a gate.
const MaxGateLines = 40

// shortDuration renders a duration without trailing zero units: 30s, 10m, 1h.
func shortDuration(d time.Duration) string {
	s := d.String()
	if strings.HasSuffix(s, "m0s") {
		s = s[:len(s)-2]
	}
	if strings.HasSuffix(s, "h0m") {
		s = s[:len(s)-2]
	}
	return s
}

// GateVerdict is the verdict line of a gate.
func GateVerdict(r gate.Result) string {
	n, p, f, sk := r.Counts()
	word, counts := "PASSED", fmt.Sprintf("%d of %d", p, n)
	if sk > 0 {
		counts += fmt.Sprintf(", %d skipped", sk)
	}
	if r.Status != result.Pass {
		word, counts = "FAILED", fmt.Sprintf("%d of %d", f, n)
	}
	timing := "spent " + Duration(r.Spent.Milliseconds())
	if r.Ceiling > 0 {
		timing = "ceiling " + shortDuration(r.Ceiling) + ", " + timing
	}
	line := fmt.Sprintf("gate: %s - %s (%s) | %s | run %s", r.Name, word, counts, timing, r.ID)
	if r.OverCeiling {
		line += " | over ceiling"
	}
	return line
}

// Gate renders the compact text of a gate: one line per passing script, one
// block per other script, then the verdict line. The text is capped at
// MaxGateLines; the cap is announced and the verdict is always kept.
func Gate(r gate.Result) string {
	var body []string
	for i, sr := range r.Scripts {
		if sr.Status == result.Pass {
			body = append(body, header(sr))
			continue
		}
		var red reduce.Reduction
		if i < len(r.Reductions) {
			red = r.Reductions[i]
		}
		block := strings.TrimRight(Run(sr, red), "\n")
		body = append(body, strings.Split(block, "\n")...)
	}
	verdict := GateVerdict(r)
	if len(body)+1 > MaxGateLines {
		body = body[:MaxGateLines-2]
		body = append(body, fmt.Sprintf("… output capped at %d lines - kh show %s", MaxGateLines, r.ID))
	}
	return strings.Join(append(body, verdict), "\n") + "\n"
}
