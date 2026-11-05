// Package reduce implements the generic, deterministic reduction of a log:
// the first lines that match a fixed error vocabulary and the last lines.
package reduce

import (
	"bufio"
	"io"
	"os"
	"regexp"
	"sort"
	"strings"
)

// Reduction tuning.
const (
	MaxMatches = 5
	TailLines  = 10
	// maxStoredLine bounds the memory kept per line; the rest of a longer line
	// is read and dropped (it stays in output.log).
	maxStoredLine = 1 << 20
)

// Vocabulary is the fixed error vocabulary.
var Vocabulary = regexp.MustCompile(`(?i)\b(error|errors|fail|failed|failure|exception|panic|traceback|fatal)\b`)

// Line is one line of output.log with its 1-based number.
type Line struct {
	N    int
	Text string
}

// Reduction is the reduced view of a log.
type Reduction struct {
	Matches, Tail []Line
	Total         int
}

// readLine returns the next line without its newline, keeping at most
// maxStoredLine bytes. ok is false at EOF with nothing read.
func readLine(r *bufio.Reader) (text string, ok bool, err error) {
	var sb strings.Builder
	got := false
	for {
		chunk, isPrefix, err := r.ReadLine()
		if err != nil {
			if err == io.EOF {
				return sb.String(), got, nil
			}
			return "", false, err
		}
		got = true
		if room := maxStoredLine - sb.Len(); room > 0 {
			if len(chunk) > room {
				chunk = chunk[:room]
			}
			sb.Write(chunk)
		}
		if !isPrefix {
			return sb.String(), true, nil
		}
	}
}

// FromFile reduces the log at path: Matches are the first MaxMatches lines that
// match Vocabulary; Tail is the last TailLines of the remaining lines.
func FromFile(path string) (Reduction, error) {
	var red Reduction
	f, err := os.Open(path)
	if err != nil {
		return red, err
	}
	defer f.Close()
	br := bufio.NewReaderSize(f, 64<<10)
	ring := make([]Line, 0, TailLines)
	next := 0 // oldest slot once the ring is full
	for n := 1; ; n++ {
		text, ok, err := readLine(br)
		if err != nil {
			return red, err
		}
		if !ok {
			break
		}
		red.Total = n
		l := Line{N: n, Text: text}
		if len(red.Matches) < MaxMatches && Vocabulary.MatchString(text) {
			red.Matches = append(red.Matches, l)
			continue
		}
		if len(ring) < TailLines {
			ring = append(ring, l)
		} else {
			ring[next] = l
			next = (next + 1) % TailLines
		}
	}
	for i := 0; i < len(ring); i++ {
		red.Tail = append(red.Tail, ring[(next+i)%len(ring)])
	}
	return red, nil
}

// Context returns the lines within radius of each given line, merged, in order.
func Context(path string, lines []Line, radius int) ([]Line, error) {
	if len(lines) == 0 {
		return nil, nil
	}
	ns := make([]int, len(lines))
	for i, l := range lines {
		ns[i] = l.N
	}
	sort.Ints(ns)
	type span struct{ lo, hi int }
	var spans []span
	for _, n := range ns {
		lo, hi := n-radius, n+radius
		if lo < 1 {
			lo = 1
		}
		if k := len(spans); k > 0 && lo <= spans[k-1].hi+1 {
			if hi > spans[k-1].hi {
				spans[k-1].hi = hi
			}
			continue
		}
		spans = append(spans, span{lo, hi})
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	br := bufio.NewReaderSize(f, 64<<10)
	var out []Line
	si := 0
	for n := 1; si < len(spans); n++ {
		text, ok, err := readLine(br)
		if err != nil {
			return nil, err
		}
		if !ok {
			break
		}
		for si < len(spans) && n > spans[si].hi {
			si++
		}
		if si < len(spans) && n >= spans[si].lo {
			out = append(out, Line{N: n, Text: text})
		}
	}
	return out, nil
}
