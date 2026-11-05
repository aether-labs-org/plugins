package script

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/baseline"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/builtin"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/config"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/redact"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/result"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/scope"
)

type finishFunc func(result.Status, string, *int) (result.Result, error)

// runBuiltin runs a builtin and turns its outcome into the result: exceptions,
// then the baseline (heuristic scripts), then the status.
func (e Exec) runBuiltin(s config.Script, scoped []string, res *result.Result, logf *os.File, red *redact.Redactor, finish finishFunc) (result.Result, error) {
	b, ok := e.registry()[s.Builtin]
	if !ok {
		return finish(result.Error, "unknown builtin "+s.Builtin, nil)
	}
	params, problems := b.Decode(s.With)
	if len(problems) > 0 {
		return finish(result.Error, "invalid with: "+strings.Join(problems, "; "), nil)
	}
	res.Attempts = 1
	files := scoped
	var err error
	if s.Files == "" {
		if e.All {
			files, err = scope.Candidates(e.Root)
		} else {
			files, err = scope.Changed(e.Root, e.Changes)
		}
		if err != nil {
			return finish(result.Error, "cannot list files: "+err.Error(), nil)
		}
	}
	base, err := scope.BranchBase(e.Root)
	if err != nil {
		return finish(result.Error, "cannot resolve the branch base: "+err.Error(), nil)
	}
	out := b.Run(builtin.Context{
		Root: e.Root, Files: files, All: e.All, Base: base, Cfg: e.Cfg, Script: s, Gate: e.Gate,
		Now: time.Now(), Measure: e.measure != nil, CommitMsgFile: e.CommitMsgFile,
	}, params)

	// the evidence log carries what the builtin found
	fmt.Fprintln(logf, red.String(out.Summary))
	for _, f := range out.Findings {
		fmt.Fprintln(logf, red.String(findingText(f)))
	}

	if e.measure != nil && out.Counts != nil {
		e.measure.counts, e.measure.counted = out.Counts, true
	}
	if out.Status == result.Skip || out.Status == result.Error {
		return finish(out.Status, out.Summary, nil)
	}

	findings, excepted := applyExceptions(s.Exceptions, out.Findings, time.Now())
	counts := out.Counts
	if excepted > 0 && counts != nil {
		counts = dropExcepted(s.Exceptions, counts, time.Now())
	}
	sortFindings(findings)
	res.Findings, res.Parsed = findings, true
	res.Counts = countSeverities(findings)
	res.Guidance = s.Guidance
	if res.Guidance == "" {
		res.Guidance = out.Guidance
	}
	suffix := ""
	if excepted > 0 {
		suffix = fmt.Sprintf(" (excepted: %d)", excepted)
	}
	status, summary := out.Status, out.Summary+suffix

	if s.Baseline != "" && e.measure == nil {
		if out.Counts == nil {
			return finish(result.Error, "builtin "+s.Builtin+" has no per-file counts: it cannot take a baseline", nil)
		}
		base, err := baseline.Read(filepath.Join(e.Root, filepath.FromSlash(s.Baseline)))
		if err != nil {
			if !isNotExist(err) {
				return finish(result.Error, "baseline: "+err.Error(), nil)
			}
			base = baseline.Baseline{Counts: map[string]int{}}
		}
		over := baseline.Compare(counts, base)
		res.Baseline = &result.Baseline{File: s.Baseline, Over: over}
		if len(over) == 0 {
			status, summary = result.Pass, fmt.Sprintf("%d files with findings, within baseline%s", len(counts), suffix)
			res.Findings = nil
		} else {
			status, summary = result.Fail, fmt.Sprintf("%d files over baseline%s", len(over), suffix)
			overFiles := map[string]bool{}
			for _, o := range over {
				overFiles[strings.SplitN(o, " ", 2)[0]] = true
			}
			var keep []result.Finding
			for _, f := range findings {
				if overFiles[f.File] {
					keep = append(keep, f)
				}
			}
			res.Findings = keep
		}
	} else if status == result.Fail && excepted > 0 && len(findings) == 0 {
		status, summary = result.Pass, fmt.Sprintf("pass%s", suffix)
	}
	if status == result.Pass {
		res.Findings = nil
	}
	return finish(status, summary, nil)
}

func findingText(f result.Finding) string {
	loc := f.File
	if f.Line > 0 {
		loc = fmt.Sprintf("%s:%d", loc, f.Line)
	}
	return strings.TrimSpace(loc + "  " + f.Rule + "  " + f.Message)
}

func dropExcepted(ex []config.Exception, counts map[string]int, now time.Time) map[string]int {
	today := now.Format("2006-01-02")
	out := map[string]int{}
	for f, n := range counts {
		covered := false
		for _, x := range ex {
			if x.Until >= today && scope.MatchOne(x.Path, f) {
				covered = true
			}
		}
		if !covered {
			out[f] = n
		}
	}
	return out
}

func isNotExist(err error) bool {
	return os.IsNotExist(err) || strings.Contains(err.Error(), "no such file")
}
