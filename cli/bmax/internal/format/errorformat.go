package format

import (
	"bufio"
	"bytes"
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/result"
)

func init() { register("errorformat", errorformat) }

// errorformat applies one regular expression with named groups
// (file, line, col, rule, severity, message) to each line of the output.
func errorformat(in Input) ([]result.Finding, bool, error) {
	re, err := regexp.Compile(in.Pattern)
	if err != nil {
		return nil, false, fmt.Errorf("invalid errorformat pattern: %v", err)
	}
	names := re.SubexpNames()
	var out []result.Finding
	last := -1 // index of the finding that continuation lines extend
	sc := bufio.NewScanner(bytes.NewReader(in.Output))
	sc.Buffer(make([]byte, 64<<10), 1<<20)
	for sc.Scan() {
		raw := strings.TrimRight(sc.Text(), "\r")
		m := re.FindStringSubmatch(raw)
		if m == nil {
			// An indented line right after a finding continues its message
			// (pyright, javac); a caret line only points at the column.
			t := strings.TrimSpace(raw)
			if last >= 0 && t == "^" {
				continue
			}
			if last >= 0 && t != "" && (raw[0] == ' ' || raw[0] == '\t') && len(out[last].Message) < maxMessage {
				out[last].Message = clip(strings.TrimSpace(out[last].Message + " " + t))
			} else {
				last = -1
			}
			continue
		}
		f := result.Finding{Severity: "error"}
		for i, n := range names {
			if n == "" || i >= len(m) {
				continue
			}
			switch n {
			case "file":
				f.File = m[i]
			case "line":
				f.Line, _ = strconv.Atoi(m[i])
			case "col":
				f.Col, _ = strconv.Atoi(m[i])
			case "rule":
				f.Rule = m[i]
			case "severity":
				f.Severity = normalizeSeverity(m[i])
			case "message":
				f.Message = clip(m[i])
			}
		}
		out = append(out, f)
		last = len(out) - 1
	}
	if err := sc.Err(); err != nil {
		return nil, false, err
	}
	// Output with no match is a clean run only if the caller trusts the exit
	// code; the parser recognises it as "no findings" (ok) either way.
	return out, true, nil
}

func normalizeSeverity(s string) string {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "warning", "warn", "w":
		return "warning"
	case "note", "info", "information", "hint", "suggestion", "convention", "refactor":
		return "note"
	}
	return "error"
}
