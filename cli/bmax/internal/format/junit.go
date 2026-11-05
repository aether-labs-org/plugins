package format

import (
	"bytes"
	"encoding/xml"
	"io"
	"strconv"
	"strings"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/result"
)

func init() { register("junit", junit) }

// maxMessage bounds a finding message.
const maxMessage = 300

// JUnitTotals counts the test cases of JUnit reports: all, failed (failure or
// error) and skipped.
type JUnitTotals struct{ Tests, Failed, Skipped int }

type junitCase struct {
	name, class, file string
	line              int
	failed, errored   bool
	skipped           bool
	message, body     string
}

// walkJUnit reads every testcase of one report. ok=false when the document is
// not a JUnit report (no testsuite or testsuites element).
func walkJUnit(report []byte) (cases []junitCase, ok bool, err error) {
	dec := xml.NewDecoder(bytes.NewReader(report))
	dec.Strict = false
	var cur *junitCase
	var stack []string
	var text strings.Builder
	sawRoot := false
	for {
		tok, terr := dec.Token()
		if terr == io.EOF {
			break
		}
		if terr != nil {
			return nil, false, terr
		}
		switch t := tok.(type) {
		case xml.StartElement:
			stack = append(stack, t.Name.Local)
			switch t.Name.Local {
			case "testsuites", "testsuite":
				sawRoot = true
			case "testcase":
				c := junitCase{}
				for _, a := range t.Attr {
					switch a.Name.Local {
					case "name":
						c.name = a.Value
					case "classname":
						c.class = a.Value
					case "file":
						c.file = a.Value
					case "line":
						c.line, _ = strconv.Atoi(a.Value)
					}
				}
				cur = &c
			case "failure", "error":
				if cur != nil {
					if t.Name.Local == "error" {
						cur.errored = true
					} else {
						cur.failed = true
					}
					for _, a := range t.Attr {
						if a.Name.Local == "message" && cur.message == "" {
							cur.message = a.Value
						}
					}
					text.Reset()
				}
			case "skipped":
				if cur != nil {
					cur.skipped = true
				}
			}
		case xml.CharData:
			if cur != nil && len(stack) > 0 && (stack[len(stack)-1] == "failure" || stack[len(stack)-1] == "error") {
				text.Write(t)
			}
		case xml.EndElement:
			if len(stack) > 0 {
				stack = stack[:len(stack)-1]
			}
			switch t.Name.Local {
			case "failure", "error":
				if cur != nil && cur.body == "" {
					cur.body = text.String()
				}
			case "testcase":
				if cur != nil {
					cases = append(cases, *cur)
					cur = nil
				}
			}
		}
	}
	return cases, sawRoot, nil
}

func firstLine(s string) string {
	for _, l := range strings.Split(s, "\n") {
		if l = strings.TrimSpace(l); l != "" {
			return l
		}
	}
	return ""
}

func clip(s string) string {
	if len(s) > maxMessage {
		return s[:maxMessage] + "…"
	}
	return s
}

func junitFinding(c junitCase) result.Finding {
	f := result.Finding{File: c.file, Line: c.line, Rule: strings.TrimSpace(c.name), Severity: "error"}
	if f.File == "" && strings.TrimSpace(c.class) != strings.TrimSpace(c.name) {
		f.File = strings.TrimSpace(c.class)
	}
	msg := firstLine(c.message)
	if msg == "" {
		msg = firstLine(c.body)
	}
	f.Message = clip(msg)
	return f
}

// junit reads JUnit XML reports: a failing or erroring test case is an error
// finding; a skipped one is not a finding.
func junit(in Input) ([]result.Finding, bool, error) {
	reports := docs(in)
	if len(reports) == 0 {
		return nil, false, nil
	}
	var out []result.Finding
	for _, r := range reports {
		cases, ok, err := walkJUnit(r)
		if err != nil || !ok {
			return nil, false, nil
		}
		for _, c := range cases {
			if c.failed || c.errored {
				out = append(out, junitFinding(c))
			}
		}
	}
	return out, true, nil
}

// TotalsJUnit counts the test cases of the reports; ok=false when they are not JUnit.
func TotalsJUnit(reports [][]byte) (JUnitTotals, bool) {
	var t JUnitTotals
	for _, r := range reports {
		cases, ok, err := walkJUnit(r)
		if err != nil || !ok {
			return JUnitTotals{}, false
		}
		for _, c := range cases {
			t.Tests++
			if c.failed || c.errored {
				t.Failed++
			} else if c.skipped {
				t.Skipped++
			}
		}
	}
	return t, len(reports) > 0
}
