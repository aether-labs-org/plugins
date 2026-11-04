package script

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/aether-labs-org/plugins/cli/kh/internal/config"
	"github.com/aether-labs-org/plugins/cli/kh/internal/result"
	"github.com/aether-labs-org/plugins/cli/kh/internal/scope"
)

func git(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false"}, args...)...)
	cmd.Dir = dir
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
}

func write(t *testing.T, dir, name, body string) {
	t.Helper()
	p := filepath.Join(dir, name)
	os.MkdirAll(filepath.Dir(p), 0o755)
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

// newExec makes a git repository (one seed commit) and an Exec over cfg.
func newExec(t *testing.T, yml string) (Exec, string) {
	t.Helper()
	d, _ := filepath.EvalSymlinks(t.TempDir())
	git(t, d, "init", "-q", ".")
	write(t, d, ".agents/keel.yml", yml)
	write(t, d, ".gitignore", ".agents/run/\n")
	git(t, d, "add", "-A")
	git(t, d, "commit", "-q", "-m", "seed")
	c, err := config.Parse([]byte(yml))
	if err != nil {
		t.Fatalf("config: %v", err)
	}
	return Exec{Root: d, Cfg: c, Changes: scope.Worktree, KhVersion: "test"}, d
}

func runScript(t *testing.T, e Exec, id string, extra ...string) result.Result {
	t.Helper()
	res, err := e.Script(context.Background(), id, extra)
	if err != nil {
		t.Fatalf("Script(%s): %v", id, err)
	}
	return res
}

func logOf(t *testing.T, root string, res result.Result) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(root, res.Evidence.Log))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestShortFormExitCodes(t *testing.T) {
	e, _ := newExec(t, "version: 1\nscripts:\n  ok: \"true\"\n  bad: \"false\"\n")
	if r := runScript(t, e, "ok"); r.Status != result.Pass || *r.ExitCode != 0 || r.Script != "ok" {
		t.Errorf("ok: %+v", r)
	}
	if r := runScript(t, e, "bad"); r.Status != result.Fail || *r.ExitCode != 1 {
		t.Errorf("bad: %+v", r)
	}
	if _, err := e.Script(context.Background(), "nope", nil); err == nil {
		t.Error("unknown script accepted")
	}
}

func TestReportPlaceholder(t *testing.T) {
	e, d := newExec(t, `version: 1
scripts:
  rep:
    run: printf x > {report}
    reports: "{report}"
`)
	r := runScript(t, e, "rep")
	if r.Status != result.Pass {
		t.Fatalf("status %s: %s", r.Status, r.Summary)
	}
	if len(r.Evidence.Reports) != 1 {
		t.Fatalf("reports = %v", r.Evidence.Reports)
	}
	b, err := os.ReadFile(filepath.Join(d, r.Evidence.Reports[0]))
	if err != nil || string(b) != "x" {
		t.Fatalf("report content %q, %v", b, err)
	}
	if !strings.HasPrefix(r.Evidence.Reports[0], r.Evidence.Dir) {
		t.Errorf("report %s outside evidence %s", r.Evidence.Reports[0], r.Evidence.Dir)
	}
}

func TestReportMissingIsError(t *testing.T) {
	e, _ := newExec(t, "version: 1\nscripts:\n  rep: { run: \"true\", reports: \"{report}\" }\n")
	r := runScript(t, e, "rep")
	if r.Status != result.Error || !strings.Contains(r.Summary, "declared report missing") {
		t.Fatalf("%s: %s", r.Status, r.Summary)
	}
}

func TestReportCopiedFromElsewhere(t *testing.T) {
	e, d := newExec(t, "version: 1\nscripts:\n  rep: { run: \"mkdir -p out && echo '<a/>' > out/r.xml\", reports: \"out/*.xml\" }\n")
	r := runScript(t, e, "rep")
	if r.Status != result.Pass || len(r.Evidence.Reports) != 1 {
		t.Fatalf("%s %s %v", r.Status, r.Summary, r.Evidence.Reports)
	}
	if !strings.Contains(r.Evidence.Reports[0], "reports/") {
		t.Errorf("not copied into evidence: %s", r.Evidence.Reports[0])
	}
	if _, err := os.Stat(filepath.Join(d, r.Evidence.Reports[0])); err != nil {
		t.Error(err)
	}
}

func TestStaleReportIsError(t *testing.T) {
	e, d := newExec(t, "version: 1\nscripts:\n  rep: { run: \"true\", reports: \"out/r.xml\" }\n")
	write(t, d, "out/r.xml", "<old/>")
	old := time.Now().Add(-time.Hour)
	os.Chtimes(filepath.Join(d, "out/r.xml"), old, old)
	r := runScript(t, e, "rep")
	if r.Status != result.Error {
		t.Fatalf("stale report accepted: %s %s", r.Status, r.Summary)
	}
}

func TestFilesAppendedQuoted(t *testing.T) {
	e, d := newExec(t, "version: 1\nscripts:\n  show: { run: \"printf '%s\\\\n'\", files: \"*.ts\" }\n")
	write(t, d, "My File.ts", "1")
	write(t, d, "-rf.ts", "1")
	write(t, d, "other.js", "1")
	r := runScript(t, e, "show")
	if r.Status != result.Pass {
		t.Fatalf("%s: %s", r.Status, r.Summary)
	}
	log := logOf(t, d, r)
	if log != "-rf.ts\nMy File.ts\n" {
		t.Errorf("log = %q", log)
	}
}

func TestPassFilesFalse(t *testing.T) {
	e, d := newExec(t, "version: 1\nscripts:\n  show: { run: \"echo args: $#\", files: \"*.ts\", pass_files: false }\n")
	if r := runScript(t, e, "show"); r.Status != result.Skip || r.Summary != "no changed files in scope" {
		t.Fatalf("no match: %s %s", r.Status, r.Summary)
	}
	write(t, d, "a.ts", "1")
	r := runScript(t, e, "show")
	if r.Status != result.Pass || !strings.Contains(logOf(t, d, r), "args: 0") {
		t.Fatalf("%s: %q", r.Status, logOf(t, d, r))
	}
}

func TestNoMatchSkip(t *testing.T) {
	e, d := newExec(t, "version: 1\nscripts:\n  lint: { run: \"false\", files: \"*.ts\" }\n")
	write(t, d, "a.js", "1")
	r := runScript(t, e, "lint")
	if r.Status != result.Skip || r.Summary != "no changed files in scope" || r.ExitCode != nil {
		t.Fatalf("%+v", r)
	}
}

func TestRequiresMissingSkip(t *testing.T) {
	e, _ := newExec(t, "version: 1\nscripts:\n  s: { run: \"true\", requires: [definitely-missing-tool] }\n")
	r := runScript(t, e, "s")
	if r.Status != result.Skip || r.Summary != "definitely-missing-tool not found - install it (see AGENTS.md)" {
		t.Fatalf("%s: %s", r.Status, r.Summary)
	}
}

func TestExit127Skip(t *testing.T) {
	e, _ := newExec(t, "version: 1\nscripts:\n  s: definitely-missing-tool --flag\n")
	r := runScript(t, e, "s")
	if r.Status != result.Skip || r.Summary != "definitely-missing-tool not found - install it (see AGENTS.md)" {
		t.Fatalf("%s: %s", r.Status, r.Summary)
	}
}

func TestRetryFlaky(t *testing.T) {
	e, d := newExec(t, `version: 1
scripts:
  flaky:
    run: 'n=$(cat count 2>/dev/null || echo 0); echo $((n+1)) > count; [ "$n" -ge 1 ]'
    retries: 1
`)
	r := runScript(t, e, "flaky")
	if r.Status != result.Pass || r.Summary != "pass (flaky: 2/2)" || r.Attempts != 2 {
		t.Fatalf("%s %q attempts=%d", r.Status, r.Summary, r.Attempts)
	}
	_ = d
}

func TestRetriesExhausted(t *testing.T) {
	e, _ := newExec(t, "version: 1\nscripts:\n  bad: { run: \"false\", retries: 2 }\n")
	r := runScript(t, e, "bad")
	if r.Status != result.Fail || r.Attempts != 3 {
		t.Fatalf("%s attempts=%d", r.Status, r.Attempts)
	}
}

func TestErrorNotRetried(t *testing.T) {
	e, _ := newExec(t, "version: 1\nscripts:\n  slow: { run: \"sleep 5\", retries: 2, timeout: 1s }\n")
	start := time.Now()
	r := runScript(t, e, "slow")
	if r.Status != result.Error || r.Attempts != 1 {
		t.Fatalf("%s attempts=%d: %s", r.Status, r.Attempts, r.Summary)
	}
	if time.Since(start) > 4*time.Second {
		t.Errorf("took %v", time.Since(start))
	}
}

func TestAllBatches(t *testing.T) {
	e, d := newExec(t, "version: 1\nscripts:\n  cnt: { run: \"sh -c 'echo call; test $# -lt 99' sh\", files: \"*.txt\" }\n")
	for i := 0; i < 30; i++ {
		write(t, d, fmt.Sprintf("dir/file-number-%02d.txt", i), "x")
	}
	git(t, d, "add", "-A")
	git(t, d, "commit", "-q", "-m", "files")
	e.All = true
	e.MaxArg = 200 // ~ 6 files of 25 bytes per batch
	r := runScript(t, e, "cnt")
	if r.Status != result.Pass {
		t.Fatalf("%s: %s", r.Status, r.Summary)
	}
	if n := strings.Count(logOf(t, d, r), "call"); n < 4 {
		t.Errorf("only %d invocations: %q", n, logOf(t, d, r))
	}
	// one batch failing fails the whole script
	e.Cfg.Scripts["cnt"] = func() config.Script { s := e.Cfg.Scripts["cnt"]; s.Run = "sh -c 'test $# -gt 4' sh"; return s }()
	e.MaxArg = 120
	if r := runScript(t, e, "cnt"); r.Status != result.Fail {
		t.Errorf("merged verdict %s", r.Status)
	}
}

func TestExtraArgs(t *testing.T) {
	e, d := newExec(t, "version: 1\nscripts:\n  t: \"printf '[%s]'\"\n")
	r := runScript(t, e, "t", "-t", "foo bar")
	if got := logOf(t, d, r); got != "[-t][foo bar]" {
		t.Errorf("log = %q", got)
	}
}

func TestExecContract(t *testing.T) {
	e, d := newExec(t, "version: 1\nscripts:\n  a: { exec: ok.sh }\n  b: { exec: lie.sh }\n  c: { exec: none.sh }\n  d: { exec: skip.sh }\n  f: { exec: fail.sh }\n")
	write(t, d, "ok.sh", "printf 'a\\tcorrectness\\tpass\\tall good\\n'\nexit 0\n")
	write(t, d, "lie.sh", "printf 'b\\theuristic\\tpass\\tfine\\n'\nexit 1\n")
	write(t, d, "none.sh", "echo hello\nexit 0\n")
	write(t, d, "skip.sh", "printf 'd\\theuristic\\tskip\\tno tool\\n'\nexit 2\n")
	write(t, d, "fail.sh", "printf 'f\\theuristic\\tfail\\tbad\\n'\nexit 1\n")
	if r := runScript(t, e, "a"); r.Status != result.Pass || r.Summary != "all good" {
		t.Errorf("a: %s %q", r.Status, r.Summary)
	}
	if r := runScript(t, e, "b"); r.Status != result.Error || !strings.Contains(r.Summary, "exec contract violated") {
		t.Errorf("b: %s %q", r.Status, r.Summary)
	}
	if r := runScript(t, e, "c"); r.Status != result.Error || !strings.Contains(r.Summary, "exec contract violated") {
		t.Errorf("c: %s %q", r.Status, r.Summary)
	}
	if r := runScript(t, e, "d"); r.Status != result.Skip || r.Summary != "no tool" {
		t.Errorf("d: %s %q", r.Status, r.Summary)
	}
	if r := runScript(t, e, "f"); r.Status != result.Fail || r.Summary != "bad" {
		t.Errorf("f: %s %q", r.Status, r.Summary)
	}
}

func TestCommandQuoting(t *testing.T) {
	s := config.Script{Run: "tool --out {report}"}
	argv := Command(s, []string{"a b.ts", "it's.ts", "-x.ts", "plain.ts"}, []string{"--flag"}, "/tmp/my dir/report")
	if argv[0] != "bash" || argv[3] != "-c" {
		t.Fatalf("argv = %q", argv)
	}
	want := `tool --out '/tmp/my dir/report' 'a b.ts' 'it'\''s.ts' -x.ts plain.ts --flag`
	if argv[4] != want {
		t.Errorf("got  %s\nwant %s", argv[4], want)
	}
}

func TestEvidenceAndSecretsRedacted(t *testing.T) {
	e, d := newExec(t, "version: 1\nscripts:\n  leak: \"echo ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"\n")
	r := runScript(t, e, "leak")
	if strings.Contains(logOf(t, d, r), "ghp_aaaa") {
		t.Error("token in the evidence log")
	}
	if _, err := os.Stat(filepath.Join(d, r.Evidence.Dir, "meta.json")); err != nil {
		t.Error(err)
	}
}

const efPattern = `'^(?P<file>[^:]+):(?P<line>\d+): (?P<message>.*)$'`

func writeBaseline(t *testing.T, d, name, rows string) {
	t.Helper()
	write(t, d, name, "# measured_at: 2026-11-04 review_by: 2027-05-04\n"+rows)
}

func lintYML(extra string) string {
	return "version: 1\nscripts:\n  lint:\n    run: \"printf 'a.ts:1: m1\\\\na.ts:2: m2\\\\na.ts:3: m3\\\\nb.ts:9: m4\\\\n'; exit 1\"\n    format: errorformat\n    pattern: " + efPattern + "\n    class: heuristic\n" + extra
}

func TestBaselinedStatusIgnoresExit(t *testing.T) {
	e, d := newExec(t, lintYML("    baseline: .agents/baselines/lint.tsv\n"))
	writeBaseline(t, d, ".agents/baselines/lint.tsv", "a.ts\t3\nb.ts\t1\n")
	r := runScript(t, e, "lint")
	if r.Status != result.Pass || r.ExitCode == nil || *r.ExitCode != 1 || r.Baseline == nil || len(r.Baseline.Over) != 0 {
		t.Fatalf("status=%s exit=%v baseline=%+v summary=%q", r.Status, r.ExitCode, r.Baseline, r.Summary)
	}
	writeBaseline(t, d, ".agents/baselines/lint.tsv", "a.ts\t2\n")
	r = runScript(t, e, "lint")
	if r.Status != result.Fail || len(r.Baseline.Over) != 2 || r.Baseline.Over[0] != "a.ts 3>2" || r.Baseline.Over[1] != "b.ts 1>0" {
		t.Fatalf("status=%s baseline=%+v", r.Status, r.Baseline)
	}
	if len(r.Findings) != 4 {
		t.Errorf("findings of over files should be listed: %v", r.Findings)
	}
}

func TestBaselineMissingFileAllowsNothing(t *testing.T) {
	e, _ := newExec(t, lintYML("    baseline: .agents/baselines/lint.tsv\n"))
	if r := runScript(t, e, "lint"); r.Status != result.Fail {
		t.Fatalf("status=%s", r.Status)
	}
}

func TestBaselineMalformedIsError(t *testing.T) {
	e, d := newExec(t, lintYML("    baseline: .agents/baselines/lint.tsv\n"))
	write(t, d, ".agents/baselines/lint.tsv", "garbage\n")
	if r := runScript(t, e, "lint"); r.Status != result.Error || !strings.Contains(r.Summary, "baseline:") {
		t.Fatalf("status=%s %q", r.Status, r.Summary)
	}
}

func TestBaselinedBrokenToolIsError(t *testing.T) {
	yml := "version: 1\nscripts:\n  lint:\n    run: \"echo crashed; exit 1\"\n    format: errorformat\n    pattern: " + efPattern + "\n    class: heuristic\n    baseline: .agents/baselines/lint.tsv\n"
	e, d := newExec(t, yml)
	writeBaseline(t, d, ".agents/baselines/lint.tsv", "")
	if r := runScript(t, e, "lint"); r.Status != result.Error {
		t.Fatalf("a crash with no findings must not compare as clean: %s %q", r.Status, r.Summary)
	}
}

func TestMeasurePrintsOnly(t *testing.T) {
	e, d := newExec(t, lintYML("    baseline: .agents/baselines/lint.tsv\n"))
	before := treeListing(t, d)
	counts, err := e.Measure(context.Background(), "lint")
	if err != nil {
		t.Fatal(err)
	}
	if counts["a.ts"] != 3 || counts["b.ts"] != 1 || len(counts) != 2 {
		t.Errorf("counts = %v", counts)
	}
	if after := treeListing(t, d); after != before {
		t.Errorf("Measure changed the tree:\n%s\n---\n%s", before, after)
	}
	e2, _ := newExec(t, "version: 1\nscripts:\n  plain: \"true\"\n")
	if _, err := e2.Measure(context.Background(), "plain"); err != ErrNoCounts {
		t.Errorf("err = %v", err)
	}
}

// treeListing lists the files outside .agents/run (evidence is allowed to change).
func treeListing(t *testing.T, d string) string {
	t.Helper()
	var out []string
	filepath.Walk(d, func(p string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() && (info.Name() == ".git" || info.Name() == "run") {
			if info != nil && info.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if !info.IsDir() {
			out = append(out, fmt.Sprintf("%s %d", strings.TrimPrefix(p, d), info.Size()))
		}
		return nil
	})
	return strings.Join(out, "\n")
}

func TestExceptionDropsFindings(t *testing.T) {
	tomorrow := time.Now().AddDate(0, 0, 1).Format("2006-01-02")
	yesterday := time.Now().AddDate(0, 0, -1).Format("2006-01-02")
	live := "    exceptions:\n      - { path: \"*.ts\", until: " + tomorrow + " }\n"
	e, _ := newExec(t, lintYML(live))
	r := runScript(t, e, "lint")
	if r.Status != result.Pass || !strings.Contains(r.Summary, "excepted: 4") || len(r.Findings) != 0 {
		t.Fatalf("live exception: status=%s %q findings=%v", r.Status, r.Summary, r.Findings)
	}
	expired := "    exceptions:\n      - { path: \"*.ts\", until: " + yesterday + " }\n"
	e, _ = newExec(t, lintYML(expired))
	r = runScript(t, e, "lint")
	if r.Status != result.Fail || len(r.Findings) != 4 {
		t.Fatalf("expired exception: status=%s findings=%v", r.Status, r.Findings)
	}
	partial := "    exceptions:\n      - { path: \"a.ts\", until: " + tomorrow + " }\n"
	e, _ = newExec(t, lintYML(partial))
	r = runScript(t, e, "lint")
	if r.Status != result.Fail || len(r.Findings) != 1 || r.Findings[0].File != "b.ts" {
		t.Fatalf("partial exception: status=%s findings=%v", r.Status, r.Findings)
	}
}

func TestAbsolutePathsNormalised(t *testing.T) {
	e, d := newExec(t, "version: 1\nscripts:\n  lint:\n    run: \"echo "+"'"+"ROOT/src/a.ts:1: m"+"'"+"; exit 1\"\n    format: errorformat\n    pattern: "+efPattern+"\n")
	s := e.Cfg.Scripts["lint"]
	s.Run = strings.ReplaceAll(s.Run, "ROOT", d)
	e.Cfg.Scripts["lint"] = s
	r := runScript(t, e, "lint")
	if len(r.Findings) != 1 || r.Findings[0].File != "src/a.ts" || !r.Parsed {
		t.Fatalf("findings = %+v parsed=%v", r.Findings, r.Parsed)
	}
}

func TestNonZeroNeverPass(t *testing.T) {
	e, _ := newExec(t, `version: 1
scripts:
  test:
    run: "echo '<testsuites tests=\"0\"/>' > {report}; exit 1"
    format: junit
    reports: "{report}"
`)
	r := runScript(t, e, "test")
	if r.Status != result.Fail || !r.Parsed || len(r.Findings) != 0 {
		t.Fatalf("status=%s parsed=%v findings=%v", r.Status, r.Parsed, r.Findings)
	}
}

func TestJUnitFindingsFromReport(t *testing.T) {
	e, _ := newExec(t, `version: 1
scripts:
  test:
    run: "echo '<testsuite><testcase classname=\"a.B\" name=\"boom\"><failure message=\"bad\"/></testcase></testsuite>' > {report}; exit 1"
    format: junit
    reports: "{report}"
`)
	r := runScript(t, e, "test")
	if r.Status != result.Fail || len(r.Findings) != 1 || r.Findings[0].Rule != "boom" || r.Counts.Error != 1 {
		t.Fatalf("status=%s findings=%v counts=%+v", r.Status, r.Findings, r.Counts)
	}
}

func TestUnrecognisedReportKeepsExitVerdict(t *testing.T) {
	e, _ := newExec(t, `version: 1
scripts:
  test:
    run: "echo 'not xml' > {report}; exit 1"
    format: junit
    reports: "{report}"
`)
	r := runScript(t, e, "test")
	if r.Status != result.Fail || r.Parsed {
		t.Fatalf("status=%s parsed=%v", r.Status, r.Parsed)
	}
}

func TestFindingsOrder(t *testing.T) {
	yml := "version: 1\nscripts:\n  lint:\n    run: \"printf 'b.ts:5: error: e1\\\\na.ts:9: note: n1\\\\na.ts:7: warning: w1\\\\na.ts:3: error: e2\\\\n'; exit 1\"\n    format: errorformat\n    pattern: '^(?P<file>[^:]+):(?P<line>\\d+): (?P<severity>\\w+): (?P<message>.*)$'\n"
	e, _ := newExec(t, yml)
	r := runScript(t, e, "lint")
	var got []string
	for _, f := range r.Findings {
		got = append(got, fmt.Sprintf("%s:%d:%s", f.File, f.Line, f.Severity))
	}
	want := "a.ts:3:error b.ts:5:error a.ts:7:warning a.ts:9:note"
	if strings.Join(got, " ") != want {
		t.Errorf("order = %v", got)
	}
	if r.Counts.Error != 2 || r.Counts.Warning != 1 || r.Counts.Note != 1 || r.Summary != "2 errors, 1 warning, 1 note" {
		t.Errorf("counts = %+v summary=%q", r.Counts, r.Summary)
	}
}

func TestJUnitSummaryFailedOfTotal(t *testing.T) {
	e, _ := newExec(t, `version: 1
scripts:
  test:
    run: "echo '<testsuite><testcase name=\"a\"/><testcase name=\"b\"><failure message=\"x\"/></testcase><testcase name=\"c\"/></testsuite>' > {report}; exit 1"
    format: junit
    reports: "{report}"
`)
	if r := runScript(t, e, "test"); r.Summary != "1 failed of 3" {
		t.Errorf("summary = %q", r.Summary)
	}
}

const fileSizeYML = `version: 1
scripts:
  file-size:
    builtin: file-size
    with: { limit: 5, include: ["src"] }
`

func TestBuiltinBaselineAndClass(t *testing.T) {
	e, d := newExec(t, fileSizeYML+"    baseline: .agents/baselines/fs.tsv\n")
	write(t, d, "src/a.ts", strings.Repeat("x\n", 7))
	write(t, d, "src/ok.ts", "x\n")
	r := runScript(t, e, "file-size")
	if r.Status != result.Fail || r.Class != "heuristic" || r.Baseline == nil || len(r.Baseline.Over) != 1 {
		t.Fatalf("no baseline row: status=%s class=%s baseline=%+v summary=%q", r.Status, r.Class, r.Baseline, r.Summary)
	}
	if !strings.Contains(r.Guidance, "within 5 lines") || len(r.Findings) != 1 {
		t.Errorf("guidance=%q findings=%v", r.Guidance, r.Findings)
	}
	writeBaseline(t, d, ".agents/baselines/fs.tsv", "src/a.ts\t7\n")
	r = runScript(t, e, "file-size")
	if r.Status != result.Pass || len(r.Findings) != 0 {
		t.Fatalf("baselined: %s %q", r.Status, r.Summary)
	}
	write(t, d, "src/a.ts", strings.Repeat("x\n", 8))
	if r = runScript(t, e, "file-size"); r.Status != result.Fail || r.Baseline.Over[0] != "src/a.ts 8>7" {
		t.Fatalf("growth: %s %+v", r.Status, r.Baseline)
	}
	write(t, d, "src/a.ts", strings.Repeat("x\n", 4))
	if r = runScript(t, e, "file-size"); r.Status != result.Pass {
		t.Fatalf("shrink: %s", r.Status)
	}
}

func TestBuiltinMeasureAndExceptions(t *testing.T) {
	tomorrow := time.Now().AddDate(0, 0, 1).Format("2006-01-02")
	e, d := newExec(t, fileSizeYML+"    exceptions:\n      - { path: \"src/a.ts\", until: "+tomorrow+" }\n")
	write(t, d, "src/a.ts", strings.Repeat("x\n", 7))
	r := runScript(t, e, "file-size")
	if r.Status != result.Pass || !strings.Contains(r.Summary, "excepted: 1") {
		t.Fatalf("live exception: %s %q", r.Status, r.Summary)
	}
	counts, err := e.Measure(context.Background(), "file-size")
	if err != nil || counts["src/a.ts"] != 7 {
		t.Fatalf("measure ignores exceptions: %v %v", counts, err)
	}
	write(t, d, "src/b.ts", strings.Repeat("x\n", 9))
	if r = runScript(t, e, "file-size"); r.Status != result.Fail || len(r.Findings) != 1 || r.Findings[0].File != "src/b.ts" {
		t.Fatalf("other file still fails: %s %v", r.Status, r.Findings)
	}
}

func TestBuiltinWithoutCountsRejectsBaseline(t *testing.T) {
	e, d := newExec(t, "version: 1\nscripts:\n  deps:\n    builtin: dependencies\n    baseline: .agents/baselines/deps.tsv\n")
	_ = d
	r := runScript(t, e, "deps")
	if r.Status != result.Error || !strings.Contains(r.Summary, "no per-file counts") {
		t.Fatalf("%s %q", r.Status, r.Summary)
	}
}

func TestBuiltinNothingInScopeSkips(t *testing.T) {
	e, _ := newExec(t, fileSizeYML)
	r := runScript(t, e, "file-size")
	if r.Status != result.Skip || r.Summary != "no changed files in scope" {
		t.Fatalf("%s %q", r.Status, r.Summary)
	}
}

func TestBuiltinClassDefaults(t *testing.T) {
	e, _ := newExec(t, "version: 1\nscripts:\n  deps: { builtin: dependencies }\n  fs: { builtin: file-size }\n  fl: { builtin: folder-layout, with: { allowed: [\"*\"] } }\n  fl2: { builtin: folder-layout, class: heuristic, with: { allowed: [\"*\"] } }\n")
	got := map[string]string{}
	for _, id := range []string{"deps", "fs", "fl", "fl2"} {
		got[id] = runScript(t, e, id).Class
	}
	want := map[string]string{"deps": "security", "fs": "heuristic", "fl": "correctness", "fl2": "heuristic"}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("%s class = %s, want %s", k, got[k], v)
		}
	}
}
