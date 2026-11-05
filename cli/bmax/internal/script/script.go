// Package script runs one declared script of bmax.yml and turns what happened
// into a result.Result with evidence.
package script

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/bmatcuk/doublestar/v4"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/baseline"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/builtin"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/config"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/evidence"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/format"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/redact"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/result"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/run"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/scope"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/tree"
)

// Exec runs the scripts of a configuration.
type Exec struct {
	Root    string
	Cfg     *config.Config
	Changes scope.Base // from the gate; "worktree" for a lone bmax run
	All     bool       // every tracked file instead of the changed ones
	Gate    string
	MaxArg  int // default: ARG_MAX minus a margin

	// BmaxVersion is recorded in the evidence.
	BmaxVersion string

	// CommitMsgFile is the message file of the commit-msg hook (commit-message builtin).
	CommitMsgFile string

	// Builtins is the registry of builtins; nil means builtin.Default().
	Builtins builtin.Registry

	measure *measureSink // set by Measure
}

type measureSink struct {
	counts  map[string]int
	counted bool
}

// ErrNoCounts: the script reports no per-file counts (no format that yields
// findings, no counting builtin).
var ErrNoCounts = errors.New("the script reports no per-file counts")

// Measure runs script id over every tracked file and returns the findings per
// file, ignoring its baseline. Nothing is written.
func (e Exec) Measure(ctx context.Context, id string) (map[string]int, error) {
	sink := &measureSink{}
	e.All, e.measure = true, sink
	res, err := e.Script(ctx, id, nil)
	if err != nil {
		return nil, err
	}
	switch res.Status {
	case result.Error:
		return nil, fmt.Errorf("%s: %s", id, res.Summary)
	case result.Skip:
		return nil, fmt.Errorf("%s: skipped: %s", id, res.Summary)
	}
	if !sink.counted {
		return nil, ErrNoCounts
	}
	if res.ExitCode != nil && *res.ExitCode != 0 && len(sink.counts) == 0 {
		return nil, fmt.Errorf("%s: exited %d but no findings were parsed", id, *res.ExitCode)
	}
	return sink.counts, nil
}

// captureLimit bounds the output kept in memory for the parsers.
const captureLimit = 32 << 20

type capped struct {
	buf       bytes.Buffer
	truncated bool
}

func (c *capped) Write(p []byte) (int, error) {
	if room := captureLimit - c.buf.Len(); room > 0 {
		if len(p) > room {
			c.buf.Write(p[:room])
			c.truncated = true
		} else {
			c.buf.Write(p)
		}
	} else {
		c.truncated = true
	}
	return len(p), nil
}

// Class returns the effective class of a script: its own, else heuristic when
// it has a baseline, else correctness.
func Class(s config.Script) string { return classWithDefault(s, "") }

// classWithDefault is Class with the default class of the builtin, if any.
func classWithDefault(s config.Script, builtinDefault string) string {
	switch {
	case s.Class != "":
		return s.Class
	case s.Baseline != "":
		return "heuristic"
	case builtinDefault != "":
		return builtinDefault
	default:
		return "correctness"
	}
}

func (e Exec) registry() builtin.Registry {
	if e.Builtins != nil {
		return e.Builtins
	}
	return builtin.Default()
}

func rel(root, p string) string {
	r, err := filepath.Rel(root, p)
	if err != nil {
		return p
	}
	return filepath.ToSlash(r)
}

// Script runs the script id with extra arguments appended to its command.
// A returned error means bmax itself failed (no evidence directory, unknown
// script); a failing, skipped or crashed script is a Result.
func (e Exec) Script(ctx context.Context, id string, extra []string) (result.Result, error) {
	s, ok := e.Cfg.Scripts[id]
	if !ok {
		return result.Result{}, fmt.Errorf("unknown script %q", id)
	}
	red := redact.New(os.Environ())
	fp := tree.Fingerprint(e.Root)
	ev, err := evidence.Create(e.Root, time.Now())
	if err != nil {
		return result.Result{}, fmt.Errorf("cannot create evidence: %w", err)
	}
	logf, err := os.OpenFile(ev.LogPath(), os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return result.Result{}, fmt.Errorf("cannot create %s: %w", ev.LogPath(), err)
	}
	defer logf.Close()

	started := time.Now()
	res := result.Result{
		ID:          ev.ID,
		Script:      id,
		Command:     red.String(commandText(s, extra)),
		Gate:        e.Gate,
		Class:       e.classOf(s),
		Attempts:    0,
		Guidance:    s.Guidance,
		Findings:    []result.Finding{},
		Evidence:    result.Evidence{Dir: rel(e.Root, ev.Dir), Log: rel(e.Root, ev.LogPath()), Reports: []string{}},
		Tree:        fp,
		BmaxVersion: e.BmaxVersion,
		Cwd:         e.Root,
		TimeoutMS:   s.Timeout.Milliseconds(),
		StartedAt:   started.UTC(),
	}
	finish := func(st result.Status, summary string, code *int) (result.Result, error) {
		res.Status, res.Summary, res.ExitCode = st, red.String(summary), code
		res.FinishedAt = time.Now().UTC()
		res.DurationMS = res.FinishedAt.Sub(started).Milliseconds()
		if err := ev.WriteMeta(res); err != nil {
			return res, fmt.Errorf("cannot write meta.json: %w", err)
		}
		if err := evidence.Prune(e.Root, ev.ID, evidence.MaxRuns, evidence.MaxBytes); err != nil {
			fmt.Fprintf(os.Stderr, "bmax: warning: pruning old runs: %v\n", err)
		}
		return res, nil
	}

	// Scope: which files this script sees.
	var files []string
	if s.Files != "" {
		var all []string
		var err error
		if e.All {
			all, err = scope.Candidates(e.Root) // tracked and untracked-not-ignored: a greenfield repository has nothing tracked
		} else {
			all, err = scope.Changed(e.Root, e.Changes)
		}
		if err != nil {
			return finish(result.Error, "cannot list changed files: "+err.Error(), nil)
		}
		files = scope.Match(s.Files, all)
		if len(files) == 0 {
			return finish(result.Skip, "no changed files in scope", nil)
		}
	}

	for _, tool := range s.Requires {
		if _, err := exec.LookPath(tool); err != nil {
			return finish(result.Skip, tool+" not found - install it (see AGENTS.md)", nil)
		}
	}

	if s.Builtin != "" {
		return e.runBuiltin(s, files, &res, logf, red, finish)
	}
	return e.runLoop(ctx, s, files, extra, &res, ev, logf, red, finish)
}

func (e Exec) classOf(s config.Script) string {
	if s.Builtin != "" {
		if b, ok := e.registry()[s.Builtin]; ok {
			return classWithDefault(s, builtin.ClassOf(b))
		}
	}
	return Class(s)
}

func commandText(s config.Script, extra []string) string {
	switch {
	case s.Builtin != "":
		return "builtin " + s.Builtin
	case s.Exec != "":
		return strings.Join(append([]string{"exec", s.Exec}, extra...), " ")
	}
	return strings.Join(append([]string{s.Run}, extra...), " ")
}

// attemptOut is what one attempt produced.
type attemptOut struct {
	status      result.Status
	summary     string
	code        *int
	output      []byte
	reports     [][]byte // contents of the declared reports
	reportFiles []string // evidence-relative paths of the stored reports
	findings    []result.Finding
	parsed      bool
	rawCounts   map[string]int // findings per file before exceptions and baseline
}

func (e Exec) argBudget() int {
	if e.MaxArg > 0 {
		return e.MaxArg
	}
	return DefaultMaxArg()
}

func (e Exec) runLoop(ctx context.Context, s config.Script, files, extra []string, res *result.Result,
	ev evidence.Run, logf *os.File, red *redact.Redactor, finish finishFunc) (result.Result, error) {

	total := s.Retries + 1
	var last attemptOut
	for attempt := 1; attempt <= total; attempt++ {
		res.Attempts = attempt
		capture := &capped{}
		w := red.Writer(io.MultiWriter(logf, capture))
		if attempt > 1 {
			fmt.Fprintf(w, "--- attempt %d of %d ---\n", attempt, total)
		}
		last = e.attempt(ctx, s, files, extra, ev, w)
		if err := w.Close(); err != nil {
			fmt.Fprintf(os.Stderr, "bmax: writing the log: %v\n", err)
		}
		last.output = capture.buf.Bytes()
		e.interpret(s, &last, res)
		if last.status != result.Fail || attempt == total {
			break
		}
	}
	res.Evidence.Reports = last.reportFiles
	if e.measure != nil && last.parsed {
		e.measure.counts, e.measure.counted = last.rawCounts, true
	}
	summary := last.summary
	if last.status == result.Pass && res.Attempts > 1 {
		summary = fmt.Sprintf("pass (flaky: %d/%d)", res.Attempts, total)
	}
	return finish(last.status, summary, last.code)
}

var statusRank = map[result.Status]int{result.Pass: 0, result.Skip: 1, result.Fail: 2, result.Error: 3}

// attempt runs the script once over all its batches and merges the process-level
// verdicts (before parsing and baselines).
func (e Exec) attempt(ctx context.Context, s config.Script, files, extra []string, ev evidence.Run, w io.Writer) attemptOut {
	batches := [][]string{files}
	if s.Exec == "" && s.PassesFiles() && len(files) > 0 {
		fixed := len(s.Run) + 64
		for _, x := range extra {
			fixed += len(x) + 3
		}
		batches = scope.Batches(files, fixed, e.argBudget())
	}
	out := attemptOut{status: result.Pass}
	zero := 0
	out.code = &zero
	for bi, batch := range batches {
		report := ""
		if s.Reports != "" || strings.Contains(s.Run, "{report}") {
			report = filepath.Join(ev.Dir, "report")
			if bi > 0 {
				report = fmt.Sprintf("%s.%d", report, bi)
			}
		}
		var argv []string
		if s.Exec != "" {
			argv = append(append([]string{"bash", s.Exec}, batch...), extra...)
		} else {
			argv = Command(s, batch, extra, report)
		}
		o := run.Run(ctx, run.Spec{Argv: argv, Dir: e.Root, Timeout: s.Timeout}, w)
		st, summary, code := result.Classify(o, "bash", s.Timeout)
		if st == result.Fail && code != nil && *code == 127 && len(s.Requires) == 0 && s.Exec == "" {
			st, summary = result.Skip, firstWord(s.Run)+" not found - install it (see AGENTS.md)"
		}
		if code == nil {
			out.code = nil
		} else if out.code != nil && *out.code == 0 {
			c := *code
			out.code = &c
		}
		if statusRank[st] > statusRank[out.status] {
			out.status, out.summary = st, summary
		}
		if s.Reports != "" && st != result.Error && st != result.Skip {
			contents, files, err := e.collectReports(s, ev, report, o.Started, bi)
			out.reports = append(out.reports, contents...)
			out.reportFiles = append(out.reportFiles, files...)
			if err != nil {
				out.status, out.summary = result.Error, err.Error()
			}
		}
		if st == result.Error {
			break
		}
	}
	if out.summary == "" {
		out.summary = "completed"
	}
	return out
}

func firstWord(cmd string) string {
	f := strings.Fields(cmd)
	if len(f) == 0 {
		return cmd
	}
	return filepath.Base(f[0])
}

// collectReports reads the report files a batch declared (placeholder
// expanded, globs allowed, relative to the root). Files not already in the
// evidence directory are copied there. A declared report that is missing, or
// older than the run, is an error: a stale report must not pass for a fresh one.
func (e Exec) collectReports(s config.Script, ev evidence.Run, report string, started time.Time, batch int) (contents [][]byte, stored []string, err error) {
	pat := strings.ReplaceAll(s.Reports, "{report}", filepath.ToSlash(report))
	if !filepath.IsAbs(pat) {
		pat = filepath.ToSlash(filepath.Join(e.Root, pat))
	}
	matches := []string{pat}
	if strings.ContainsAny(pat, "*?[{") {
		matches, err = doublestar.FilepathGlob(pat)
		if err != nil {
			return nil, nil, fmt.Errorf("invalid reports pattern %q: %v", s.Reports, err)
		}
	}
	slack := started.Add(-2 * time.Second)
	for _, m := range matches {
		st, serr := os.Stat(m)
		if serr != nil || !st.Mode().IsRegular() || st.ModTime().Before(slack) {
			continue
		}
		b, rerr := os.ReadFile(m)
		if rerr != nil {
			continue
		}
		contents = append(contents, b)
		dest := m
		if !strings.HasPrefix(m, ev.Dir+string(filepath.Separator)) {
			dir := filepath.Join(ev.Dir, "reports")
			if merr := os.MkdirAll(dir, 0o700); merr == nil {
				dest = filepath.Join(dir, fmt.Sprintf("%d-%s", batch, filepath.Base(m)))
				if werr := os.WriteFile(dest, b, 0o600); werr != nil {
					dest = m
				}
			}
		}
		stored = append(stored, rel(e.Root, dest))
	}
	if len(contents) == 0 {
		return nil, nil, fmt.Errorf("declared report missing after the run: %s", s.Reports)
	}
	return contents, stored, nil
}

// interpret turns a process-level verdict into the final one: the exec
// contract, the parser, exceptions and the baseline. The exit code stays the
// verdict, except for a baselined script (the comparison is the verdict) and a
// script whose every failing finding is excepted.
func (e Exec) interpret(s config.Script, a *attemptOut, res *result.Result) {
	if s.Exec != "" {
		execContract(a)
		return
	}
	if a.status == result.Error || a.status == result.Skip {
		return
	}
	var findings []result.Finding
	parsed := false
	if s.Format != "" {
		if p, ok := format.Get(s.Format); ok {
			f, ok, err := p(format.Input{Output: a.output, Reports: a.reports, Pattern: s.Pattern})
			if err != nil {
				a.status, a.summary = result.Error, "cannot parse the "+s.Format+" output: "+err.Error()
				return
			}
			findings, parsed = f, ok
		}
	}
	for i := range findings {
		findings[i].File = relPath(e.Root, findings[i].File)
	}
	res.Parsed = parsed
	a.findings, a.parsed = findings, parsed
	if !parsed {
		if s.Baseline != "" && e.measure == nil {
			a.status, a.summary = result.Error, "cannot compare with the baseline: the "+s.Format+" output was not recognised"
		}
		return
	}
	a.rawCounts = countByFile(findings)
	findings, excepted := applyExceptions(s.Exceptions, findings, time.Now())
	if s.Baseline != "" && e.measure == nil {
		e.baselined(s, a, res, findings, excepted)
		return
	}
	sortFindings(findings)
	res.Findings = findings
	res.Counts = countSeverities(findings)
	if a.status == result.Fail && len(findings) > 0 {
		a.summary = findingsSummary(s.Format, a.reports, res.Counts, a.summary)
	}
	if excepted > 0 {
		a.summary = fmt.Sprintf("%s (excepted: %d)", a.summary, excepted)
		if a.status == result.Fail && len(findings) == 0 {
			a.status, a.summary = result.Pass, fmt.Sprintf("pass (excepted: %d)", excepted)
		}
	}
}

func plural(n int, word string) string {
	if n == 1 {
		return fmt.Sprintf("%d %s", n, word)
	}
	return fmt.Sprintf("%d %ss", n, word)
}

// findingsSummary describes a failed run that produced findings: "3 failed of
// 212" for JUnit, else the counts per severity.
func findingsSummary(formatName string, reports [][]byte, c result.Counts, fallback string) string {
	if formatName == "junit" {
		if t, ok := format.TotalsJUnit(reports); ok && t.Failed > 0 {
			return fmt.Sprintf("%d failed of %d", t.Failed, t.Tests)
		}
	}
	var parts []string
	if c.Error > 0 {
		parts = append(parts, plural(c.Error, "error"))
	}
	if c.Warning > 0 {
		parts = append(parts, plural(c.Warning, "warning"))
	}
	if c.Note > 0 {
		parts = append(parts, plural(c.Note, "note"))
	}
	if len(parts) == 0 {
		return fallback
	}
	return strings.Join(parts, ", ")
}

var severityRank = map[string]int{"error": 0, "warning": 1, "note": 2}

// sortFindings orders findings by severity (errors first), then file, then line.
func sortFindings(fs []result.Finding) {
	sort.SliceStable(fs, func(i, j int) bool {
		a, b := fs[i], fs[j]
		if severityRank[a.Severity] != severityRank[b.Severity] {
			return severityRank[a.Severity] < severityRank[b.Severity]
		}
		if a.File != b.File {
			return a.File < b.File
		}
		return a.Line < b.Line
	})
}

func relPath(root, p string) string {
	p = filepath.ToSlash(p)
	if filepath.IsAbs(p) {
		if r, err := filepath.Rel(root, filepath.FromSlash(p)); err == nil && !strings.HasPrefix(r, "..") {
			p = filepath.ToSlash(r)
		}
	}
	return strings.TrimPrefix(p, "./")
}

func countByFile(fs []result.Finding) map[string]int {
	m := map[string]int{}
	for _, f := range fs {
		if f.File != "" {
			m[f.File]++
		}
	}
	return m
}

func countSeverities(fs []result.Finding) result.Counts {
	var c result.Counts
	for _, f := range fs {
		switch f.Severity {
		case "warning":
			c.Warning++
		case "note":
			c.Note++
		default:
			c.Error++
		}
	}
	return c
}

// applyExceptions drops the findings of files covered by a live exception
// (until >= today). An expired exception no longer applies.
func applyExceptions(ex []config.Exception, fs []result.Finding, now time.Time) ([]result.Finding, int) {
	if len(ex) == 0 {
		return fs, 0
	}
	today := now.Format("2006-01-02")
	var live []string
	for _, x := range ex {
		if x.Until >= today {
			live = append(live, x.Path)
		}
	}
	var kept []result.Finding
	dropped := 0
	for _, f := range fs {
		covered := false
		for _, g := range live {
			if scope.MatchOne(g, f.File) {
				covered = true
				break
			}
		}
		if covered {
			dropped++
		} else {
			kept = append(kept, f)
		}
	}
	return kept, dropped
}

// baselined derives the verdict of a heuristic script from its baseline: the
// exit code of the tool is ignored.
func (e Exec) baselined(s config.Script, a *attemptOut, res *result.Result, findings []result.Finding, excepted int) {
	base, err := baseline.Read(filepath.Join(e.Root, filepath.FromSlash(s.Baseline)))
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			a.status, a.summary = result.Error, "baseline: "+err.Error()
			return
		}
		base = baseline.Baseline{Counts: map[string]int{}} // no file: nothing is allowed
	}
	if a.code != nil && *a.code != 0 && len(findings) == 0 && excepted == 0 {
		a.status, a.summary = result.Error, fmt.Sprintf("exited %d but no findings were parsed: cannot compare with the baseline", *a.code)
		return
	}
	counts := countByFile(findings)
	over := baseline.Compare(counts, base)
	res.Counts = countSeverities(findings)
	res.Baseline = &result.Baseline{File: s.Baseline, Over: over}
	suffix := ""
	if excepted > 0 {
		suffix = fmt.Sprintf(" (excepted: %d)", excepted)
	}
	if len(over) == 0 {
		a.status = result.Pass
		a.summary = fmt.Sprintf("%d findings, within baseline%s", len(findings), suffix)
		return
	}
	overFiles := map[string]bool{}
	for _, o := range over {
		overFiles[strings.SplitN(o, " ", 2)[0]] = true
	}
	for _, f := range findings {
		if overFiles[f.File] {
			res.Findings = append(res.Findings, f)
		}
	}
	sortFindings(res.Findings)
	a.status = result.Fail
	a.summary = fmt.Sprintf("%d of %d files over baseline%s", len(over), len(counts), suffix)
}

// execContract checks line 1 of an exec script against its exit code.
func execContract(a *attemptOut) {
	if a.code == nil {
		return // timed out, not found: already an error or a skip
	}
	first := string(a.output)
	if i := strings.IndexByte(first, '\n'); i >= 0 {
		first = first[:i]
	}
	first = strings.TrimRight(first, "\r")
	violate := func(reason string) {
		a.status, a.summary = result.Error, "exec contract violated: "+reason
	}
	parts := strings.Split(first, "\t")
	if len(parts) != 4 {
		violate("line 1 must be id<TAB>class<TAB>status<TAB>summary")
		return
	}
	var want result.Status
	switch parts[2] {
	case "pass":
		want = result.Pass
	case "fail":
		want = result.Fail
	case "skip":
		want = result.Skip
	default:
		violate("status must be pass, fail or skip, got " + parts[2])
		return
	}
	if *a.code != want.ExitCode() {
		violate(fmt.Sprintf("status %s but exit code %d", parts[2], *a.code))
		return
	}
	a.status, a.summary = want, parts[3]
}
