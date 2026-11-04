package format

import (
	"net/url"
	"strings"

	"github.com/aether-labs-org/plugins/cli/kh/internal/result"
)

func init() { register("sarif", sarif) }

type sarifLog struct {
	Runs []struct {
		Tool struct {
			Driver struct {
				Rules []struct {
					ID                   string `json:"id"`
					DefaultConfiguration struct {
						Level string `json:"level"`
					} `json:"defaultConfiguration"`
				} `json:"rules"`
			} `json:"driver"`
		} `json:"tool"`
		Results []struct {
			RuleID    string `json:"ruleId"`
			RuleIndex *int   `json:"ruleIndex"`
			Rule      struct {
				ID string `json:"id"`
			} `json:"rule"`
			Level   string `json:"level"`
			Message struct {
				Text     string `json:"text"`
				Markdown string `json:"markdown"`
			} `json:"message"`
			Locations []struct {
				PhysicalLocation struct {
					ArtifactLocation struct {
						URI string `json:"uri"`
					} `json:"artifactLocation"`
					Region struct {
						StartLine   int `json:"startLine"`
						StartColumn int `json:"startColumn"`
					} `json:"region"`
				} `json:"physicalLocation"`
			} `json:"locations"`
		} `json:"results"`
	} `json:"runs"`
}

// sarif reads SARIF 2.1.0. The level of a result is its own, else the default
// configuration of its rule, else "warning" (the SARIF default).
func sarif(in Input) ([]result.Finding, bool, error) {
	ds := docs(in)
	if len(ds) == 0 {
		return nil, false, nil
	}
	var out []result.Finding
	for _, d := range ds {
		var log sarifLog
		if err := jsonValue(d, &log); err != nil || log.Runs == nil {
			return nil, false, nil
		}
		for _, run := range log.Runs {
			ruleLevel := map[string]string{}
			for _, r := range run.Tool.Driver.Rules {
				ruleLevel[r.ID] = r.DefaultConfiguration.Level
			}
			for _, r := range run.Results {
				id := r.RuleID
				if id == "" {
					id = r.Rule.ID
				}
				if id == "" && r.RuleIndex != nil && *r.RuleIndex >= 0 && *r.RuleIndex < len(run.Tool.Driver.Rules) {
					id = run.Tool.Driver.Rules[*r.RuleIndex].ID
				}
				level := r.Level
				if level == "" {
					level = ruleLevel[id]
				}
				f := result.Finding{Rule: id, Severity: sarifSeverity(level)}
				msg := r.Message.Text
				if msg == "" {
					msg = r.Message.Markdown
				}
				f.Message = clip(firstLine(msg))
				if len(r.Locations) > 0 {
					loc := r.Locations[0].PhysicalLocation
					f.File = sarifPath(loc.ArtifactLocation.URI)
					f.Line, f.Col = loc.Region.StartLine, loc.Region.StartColumn
				}
				out = append(out, f)
			}
		}
	}
	return out, true, nil
}

func sarifSeverity(level string) string {
	switch level {
	case "error":
		return "error"
	case "note", "none":
		return "note"
	}
	return "warning"
}

// sarifPath turns an artifact URI into a path: file:// is dropped and percent
// escapes are decoded.
func sarifPath(uri string) string {
	if u, err := url.PathUnescape(uri); err == nil {
		uri = u
	}
	uri = strings.TrimPrefix(uri, "file://")
	return uri
}
