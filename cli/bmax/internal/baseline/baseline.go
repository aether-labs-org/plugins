// Package baseline reads, formats and compares TSV baselines: per-file counts
// a heuristic script may not exceed (a ratchet: counts may only shrink).
package baseline

import (
	"fmt"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

// Baseline is a parsed baseline file.
type Baseline struct {
	MeasuredAt, ReviewBy string
	Counts               map[string]int
}

var headerRE = regexp.MustCompile(`^# measured_at: (\d{4}-\d{2}-\d{2}) review_by: (\d{4}-\d{2}-\d{2})$`)

// Read parses a baseline file. CRLF is tolerated. A malformed line is an error
// that names its line number.
func Read(path string) (Baseline, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return Baseline{}, err
	}
	return Parse(string(b), path)
}

// Parse parses the text of a baseline; name is used in error messages.
func Parse(text, name string) (Baseline, error) {
	out := Baseline{Counts: map[string]int{}}
	lines := strings.Split(text, "\n")
	for i, line := range lines {
		line = strings.TrimRight(line, "\r")
		n := i + 1
		if line == "" && i == len(lines)-1 {
			break
		}
		if n == 1 {
			m := headerRE.FindStringSubmatch(line)
			if m == nil {
				return out, fmt.Errorf("%s: line 1: expected \"# measured_at: YYYY-MM-DD review_by: YYYY-MM-DD\"", name)
			}
			out.MeasuredAt, out.ReviewBy = m[1], m[2]
			continue
		}
		path, count, ok := strings.Cut(line, "\t")
		c, err := strconv.Atoi(count)
		if !ok || path == "" || err != nil || c < 0 {
			return out, fmt.Errorf("%s: line %d: expected \"path<TAB>count\"", name, n)
		}
		out.Counts[path] += c
	}
	return out, nil
}

// Format renders counts as a baseline: the header with the dates (review_by is
// six months after now), then one sorted "path<TAB>count" row per file; files
// with a zero count are omitted.
func Format(counts map[string]int, now time.Time) string {
	var b strings.Builder
	fmt.Fprintf(&b, "# measured_at: %s review_by: %s\n", now.Format("2006-01-02"), now.AddDate(0, 6, 0).Format("2006-01-02"))
	paths := make([]string, 0, len(counts))
	for p, c := range counts {
		if c > 0 {
			paths = append(paths, p)
		}
	}
	sort.Strings(paths)
	for _, p := range paths {
		fmt.Fprintf(&b, "%s\t%d\n", p, counts[p])
	}
	return b.String()
}

// Compare returns "path count>allowed" for every file whose count exceeds its
// baseline row (a file absent from the baseline may have zero), sorted by path.
func Compare(counts map[string]int, b Baseline) []string {
	var over []string
	for p, c := range counts {
		if allowed := b.Counts[p]; c > allowed {
			over = append(over, fmt.Sprintf("%s %d>%d", p, c, allowed))
		}
	}
	sort.Strings(over)
	return over
}

// Total is the sum of all rows.
func (b Baseline) Total() int {
	t := 0
	for _, c := range b.Counts {
		t += c
	}
	return t
}
