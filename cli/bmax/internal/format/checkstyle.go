package format

import (
	"bytes"
	"encoding/xml"
	"io"
	"strconv"
	"strings"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/result"
)

func init() { register("checkstyle", checkstyle) }

// checkstyle reads Checkstyle XML (Checkstyle, detekt, ktlint, PMD and others):
// each <error> inside a <file> is a finding; the severity is copied
// (error, warning, info -> note).
func checkstyle(in Input) ([]result.Finding, bool, error) {
	reports := docs(in)
	if len(reports) == 0 {
		return nil, false, nil
	}
	var out []result.Finding
	for _, r := range reports {
		dec := xml.NewDecoder(bytes.NewReader(r))
		dec.Strict = false
		file := ""
		root := false
		for {
			tok, err := dec.Token()
			if err == io.EOF {
				break
			}
			if err != nil {
				return nil, false, nil
			}
			se, ok := tok.(xml.StartElement)
			if !ok {
				continue
			}
			switch se.Name.Local {
			case "checkstyle":
				root = true
			case "file":
				file = ""
				for _, a := range se.Attr {
					if a.Name.Local == "name" {
						file = a.Value
					}
				}
			case "error":
				f := result.Finding{File: file, Severity: "error"}
				for _, a := range se.Attr {
					switch a.Name.Local {
					case "line":
						f.Line, _ = strconv.Atoi(a.Value)
					case "column":
						f.Col, _ = strconv.Atoi(a.Value)
					case "severity":
						f.Severity = normalizeSeverity(a.Value)
					case "message":
						f.Message = clip(firstLine(a.Value))
					case "source":
						f.Rule = a.Value
						if strings.HasPrefix(a.Value, "com.puppycrawl.") {
							f.Rule = ruleShort(a.Value)
						}
					}
				}
				out = append(out, f)
			}
		}
		if !root {
			return nil, false, nil
		}
	}
	return out, true, nil
}

// ruleShort trims a checkstyle source (a Java class name) to its last segment.
func ruleShort(s string) string {
	if i := strings.LastIndexByte(s, '.'); i >= 0 {
		return s[i+1:]
	}
	return s
}
