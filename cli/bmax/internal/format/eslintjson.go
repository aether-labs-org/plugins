package format

import "github.com/aether-labs-org/plugins/cli/bmax/internal/result"

func init() { register("eslint-json", eslintJSON) }

type eslintFile struct {
	FilePath string `json:"filePath"`
	Messages []struct {
		RuleID   *string `json:"ruleId"`
		Severity int     `json:"severity"`
		Message  string  `json:"message"`
		Line     int     `json:"line"`
		Column   int     `json:"column"`
	} `json:"messages"`
}

// eslintJSON reads `eslint -f json`: severity 2 is an error, 1 a warning.
func eslintJSON(in Input) ([]result.Finding, bool, error) {
	ds := docs(in)
	if len(ds) == 0 {
		return nil, false, nil
	}
	var out []result.Finding
	for _, d := range ds {
		var files []eslintFile
		if err := jsonValue(d, &files); err != nil {
			return nil, false, nil
		}
		for _, f := range files {
			if f.FilePath == "" && f.Messages == nil {
				return nil, false, nil
			}
			for _, m := range f.Messages {
				fi := result.Finding{File: f.FilePath, Line: m.Line, Col: m.Column, Message: clip(firstLine(m.Message)), Severity: "warning"}
				if m.Severity >= 2 {
					fi.Severity = "error"
				}
				if m.RuleID != nil {
					fi.Rule = *m.RuleID
				}
				out = append(out, fi)
			}
		}
	}
	return out, true, nil
}
