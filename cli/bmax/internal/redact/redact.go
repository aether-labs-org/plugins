// Package redact removes secrets from text on a best-effort basis: values of
// secret-looking environment variables, well-known token patterns and PEM
// private key blocks become Placeholder.
package redact

import (
	"bytes"
	"io"
	"regexp"
	"sort"
	"strings"
)

// Placeholder replaces every redacted value.
const Placeholder = "‹redacted›"

// minValueLen is the shortest env value that is redacted; shorter values would
// mangle ordinary text.
const minValueLen = 6

var patterns = []*regexp.Regexp{
	regexp.MustCompile(`\b(AKIA|ASIA)[0-9A-Z]{16}\b`),
	regexp.MustCompile(`\bgh[pousr]_[A-Za-z0-9]{36,}\b`),
	regexp.MustCompile(`\bgithub_pat_[A-Za-z0-9_]{22,}\b`),
	regexp.MustCompile(`\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b`),
}

var (
	beginKey = regexp.MustCompile(`-----BEGIN [A-Z ]*PRIVATE KEY-----`)
	endKey   = regexp.MustCompile(`-----END [A-Z ]*PRIVATE KEY-----`)
)

// Redactor redacts strings and byte streams.
type Redactor struct {
	values *strings.Replacer // nil when there is no secret env value
}

// New builds a Redactor from environment entries ("NAME=value").
func New(env []string) *Redactor {
	seen := map[string]bool{}
	var vals []string
	for _, kv := range env {
		name, value, ok := strings.Cut(kv, "=")
		if !ok || len(value) < minValueLen || !secretName(name) || seen[value] {
			continue
		}
		seen[value] = true
		vals = append(vals, value)
	}
	r := &Redactor{}
	if len(vals) == 0 {
		return r
	}
	// Longest first: the replacer compares old strings in argument order.
	sort.SliceStable(vals, func(i, j int) bool { return len(vals[i]) > len(vals[j]) })
	pairs := make([]string, 0, 2*len(vals))
	for _, v := range vals {
		pairs = append(pairs, v, Placeholder)
	}
	r.values = strings.NewReplacer(pairs...)
	return r
}

func secretName(name string) bool {
	n := strings.ToUpper(name)
	for _, w := range []string{"TOKEN", "SECRET", "PASSWORD", "CREDENTIAL"} {
		if strings.Contains(n, w) {
			return true
		}
	}
	return strings.HasSuffix(n, "_KEY")
}

// String redacts a single string (no private-key block handling).
func (r *Redactor) String(s string) string {
	if r.values != nil {
		s = r.values.Replace(s)
	}
	for _, p := range patterns {
		s = p.ReplaceAllString(s, Placeholder)
	}
	return s
}

// Writer returns a line-buffered writer that redacts what it passes to dst.
// Close flushes a final line without newline; it does not close dst.
func (r *Redactor) Writer(dst io.Writer) io.WriteCloser {
	return &writer{r: r, dst: dst}
}

type writer struct {
	r     *Redactor
	dst   io.Writer
	buf   []byte
	inKey bool
	err   error
}

func (w *writer) Write(p []byte) (int, error) {
	if w.err != nil {
		return 0, w.err
	}
	w.buf = append(w.buf, p...)
	for {
		i := bytes.IndexByte(w.buf, '\n')
		if i < 0 {
			break
		}
		line := string(w.buf[:i])
		w.buf = w.buf[i+1:]
		if err := w.emit(line, true); err != nil {
			w.err = err
			return len(p), err
		}
	}
	return len(p), nil
}

func (w *writer) Close() error {
	if w.err != nil {
		return w.err
	}
	if len(w.buf) > 0 {
		line := string(w.buf)
		w.buf = nil
		return w.emit(line, false)
	}
	return nil
}

// emit processes one complete line (without its newline).
func (w *writer) emit(line string, newline bool) error {
	var out string
	switch {
	case w.inKey:
		if endKey.MatchString(line) {
			w.inKey = false
		}
		return nil
	case beginKey.MatchString(line):
		out = Placeholder
		if !endKey.MatchString(line) {
			w.inKey = true
		}
	default:
		out = w.r.String(line)
	}
	if newline {
		out += "\n"
	}
	_, err := io.WriteString(w.dst, out)
	return err
}

// Contains reports whether s holds a well-known token pattern or a private key
// header (the same set Redactor.String removes; environment values are not
// part of it).
func Contains(s string) bool {
	for _, re := range patterns {
		if re.MatchString(s) {
			return true
		}
	}
	return beginKey.MatchString(s)
}
