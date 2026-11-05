// Package format parses what a tool reported (a report file or its output) into
// findings. Parsing is per format, not per tool.
package format

import (
	"bytes"
	"encoding/json"
	"errors"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/result"
)

// Input is what a parser may read.
type Input struct {
	Output  []byte   // combined stdout and stderr of the run
	Reports [][]byte // contents of the declared report files
	Pattern string   // errorformat: the regular expression
}

// Parser turns tool output into findings. ok=false means the output was not
// recognised: the caller falls back to the generic reduction (parsed=false).
// A parser never decides the verdict; it only enriches it.
type Parser func(in Input) (findings []result.Finding, ok bool, err error)

var parsers = map[string]Parser{}

// Register makes a parser available under name.
func register(name string, p Parser) { parsers[name] = p }

// Get returns the parser of a format.
func Get(name string) (Parser, bool) {
	p, ok := parsers[name]
	return p, ok
}

// Names lists the registered formats (for tests).
func Names() []string {
	var out []string
	for n := range parsers {
		out = append(out, n)
	}
	return out
}

// docs returns the documents to parse: the declared reports, else the output.
func docs(in Input) [][]byte {
	if len(in.Reports) > 0 {
		return in.Reports
	}
	if len(bytes.TrimSpace(in.Output)) > 0 {
		return [][]byte{in.Output}
	}
	return nil
}

// jsonValue decodes the first JSON value of b that starts at the beginning of a
// line, so that npm or tool noise before it is tolerated.
func jsonValue(b []byte, v any) error {
	start := -1
	for i := 0; i < len(b); i++ {
		if (i == 0 || b[i-1] == '\n') && (b[i] == '[' || b[i] == '{') {
			start = i
			break
		}
	}
	if start < 0 {
		return errors.New("no JSON document")
	}
	return json.NewDecoder(bytes.NewReader(b[start:])).Decode(v)
}
