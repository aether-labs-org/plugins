package cli_test

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/aether-labs-org/plugins/cli/kh/internal/cli"
)

func run(args ...string) (string, string, int) {
	var out, errb bytes.Buffer
	rc := cli.Run(args, &out, &errb)
	return out.String(), errb.String(), rc
}

func TestVersion(t *testing.T) {
	out, _, rc := run("version")
	if out != "kh 0.5.0-dev\n" || rc != 0 {
		t.Fatalf("out=%q rc=%d", out, rc)
	}
}

func TestUsage(t *testing.T) {
	for _, args := range [][]string{{}, {"bogus"}} {
		out, errb, rc := run(args...)
		if rc != cli.ExitUsage {
			t.Fatalf("%v: rc=%d", args, rc)
		}
		if out != "" || errb == "" {
			t.Fatalf("%v: stdout=%q stderr=%q", args, out, errb)
		}
	}
}

func repo(t *testing.T) string {
	t.Helper()
	d, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if out, err := exec.Command("git", "-C", d, "init", "-q", ".").CombinedOutput(); err != nil {
		t.Fatalf("git init: %v\n%s", err, out)
	}
	if err := os.MkdirAll(filepath.Join(d, ".agents"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(d, ".agents", "keel.yml"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	t.Chdir(d)
	return d
}

func TestRunUsageErrors(t *testing.T) {
	cases := [][]string{
		{"run"},
		{"run", "a", "b"},                       // extra argument without --
		{"run", "--"},                           // no command
		{"run", "--timeout", "x", "--", "true"}, // bad duration
		{"run", "--timeout"},                    // missing value
		{"run", "--timeout=-1s", "--", "true"},  // non-positive duration
		{"run", "--bogus", "--", "true"},        // unknown flag
		{"show"},
		{"show", "a", "b"},
		{"show", "20000101-000000-dead", "--bogus"},
		{"show", "20000101-000000-dead", "--full", "--json"},
	}
	for _, args := range cases {
		out, errb, rc := run(args...)
		if rc != cli.ExitUsage || out != "" || errb == "" {
			t.Errorf("%v: rc=%d stdout=%q stderr=%q", args, rc, out, errb)
		}
	}
}

func TestRunNoKeelYml(t *testing.T) {
	d := t.TempDir()
	if out, err := exec.Command("git", "-C", d, "init", "-q", ".").CombinedOutput(); err != nil {
		t.Fatalf("git init: %v\n%s", err, out)
	}
	t.Chdir(d)
	_, errb, rc := run("run", "--", "true")
	if rc != cli.ExitError || !strings.Contains(errb, "no .agents/keel.yml at the repository root") {
		t.Fatalf("rc=%d stderr=%q", rc, errb)
	}
}

func TestRunNotGit(t *testing.T) {
	t.Chdir(t.TempDir())
	_, errb, rc := run("run", "--", "true")
	if rc != cli.ExitError || !strings.Contains(errb, "not a git repository") {
		t.Fatalf("rc=%d stderr=%q", rc, errb)
	}
}

func TestRunJSONFlagPlacement(t *testing.T) {
	repo(t)
	// --json before -- is ours; after -- it belongs to the command.
	out, errb, rc := run("run", "--json", "--", "echo", "--json")
	if rc != 0 {
		t.Fatalf("rc=%d stderr=%q out=%q", rc, errb, out)
	}
	var res map[string]any
	if err := json.Unmarshal([]byte(out), &res); err != nil {
		t.Fatalf("not JSON: %v\n%s", err, out)
	}
	if res["command"] != "echo --json" || res["status"] != "pass" {
		t.Fatalf("%v", res)
	}
}

func TestShowUnknownRun(t *testing.T) {
	repo(t)
	for _, id := range []string{"20000101-000000-dead", "../x"} {
		_, errb, rc := run("show", id)
		if rc != cli.ExitUsage || !strings.Contains(errb, "no run "+id) {
			t.Errorf("%s: rc=%d stderr=%q", id, rc, errb)
		}
	}
}

func writeKeel(t *testing.T, root, body string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(root, ".agents", "keel.yml"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

const minimalKeel = `version: 1
scripts:
  lint: "true"
gates:
  fast: { scripts: [guard, lint] }
  commit: { scripts: [guard, lint], changes: staged }
  slow: { scripts: [guard, lint], changes: branch }
  extra: { scripts: [lint] }
`

func TestValidateValid(t *testing.T) {
	r := repo(t)
	writeKeel(t, r, minimalKeel)
	out, errb, rc := run("validate")
	if rc != 0 || out != "" || errb != "" {
		t.Fatalf("rc=%d out=%q err=%q", rc, out, errb)
	}
}

func TestValidateInvalid(t *testing.T) {
	r := repo(t)
	writeKeel(t, r, "version: 2\ncolour: red\n")
	_, errb, rc := run("validate")
	if rc != cli.ExitError {
		t.Fatalf("rc=%d", rc)
	}
	if !strings.Contains(errb, "keel.yml: unknown key \"colour\"") {
		t.Errorf("stderr = %q", errb)
	}
}

func TestSchemaCommand(t *testing.T) {
	out, _, rc := run("schema", "keel")
	if rc != 0 || !json.Valid([]byte(out)) {
		t.Fatalf("rc=%d valid=%v", rc, json.Valid([]byte(out)))
	}
	if _, _, rc := run("schema", "nope"); rc != cli.ExitUsage {
		t.Fatalf("unknown schema rc=%d", rc)
	}
	if _, _, rc := run("schema"); rc != cli.ExitUsage {
		t.Fatalf("no name rc=%d", rc)
	}
}

func TestRunDeclaredScript(t *testing.T) {
	r := repo(t)
	writeKeel(t, r, minimalKeel)
	out, errb, rc := run("run", "lint")
	if rc != 0 || !strings.Contains(out, "lint  PASS") {
		t.Fatalf("rc=%d out=%q err=%q", rc, out, errb)
	}
	if _, errb, rc := run("run", "nope"); rc != cli.ExitUsage || !strings.Contains(errb, `unknown script "nope"`) {
		t.Fatalf("unknown: rc=%d err=%q", rc, errb)
	}
	if _, _, rc := run("run", "--timeout", "5s", "lint"); rc != cli.ExitUsage {
		t.Fatalf("--timeout on a script: rc=%d", rc)
	}
}

func TestRunDeclaredScriptPinMismatch(t *testing.T) {
	r := repo(t)
	writeKeel(t, r, minimalKeel)
	lockText := "version=9.9.9\n"
	for _, p := range []string{"linux-amd64", "linux-arm64", "darwin-amd64", "darwin-arm64"} {
		lockText += p + "=" + strings.Repeat("a", 64) + "\n"
	}
	os.WriteFile(filepath.Join(r, ".agents", "keel.lock"), []byte(lockText), 0o644)
	_, errb, rc := run("run", "lint")
	if rc != cli.ExitError || !strings.Contains(errb, "pin mismatch: keel.lock pins 9.9.9, this kh is 0.5.0-dev") {
		t.Fatalf("rc=%d err=%q", rc, errb)
	}
	// kh run -- <cmd>, show, validate and version are exempt
	if _, _, rc := run("run", "--", "true"); rc != 0 {
		t.Errorf("run -- exempt: rc=%d", rc)
	}
	if _, _, rc := run("validate"); rc != 0 {
		t.Errorf("validate exempt: rc=%d", rc)
	}
}

func TestGateCommand(t *testing.T) {
	r := repo(t)
	writeKeel(t, r, minimalKeel)
	out, errb, rc := run("gate", "extra")
	if rc != 0 || !strings.Contains(out, "gate: extra - PASSED (1 of 1)") {
		t.Fatalf("rc=%d out=%q err=%q", rc, out, errb)
	}
	id := out[strings.LastIndex(out, "run ")+4:]
	id = strings.TrimSpace(id)
	shown, _, rc := run("show", id)
	if rc != 0 || !strings.Contains(shown, "gate: extra - PASS") || !strings.Contains(shown, "lint  PASS") {
		t.Fatalf("show gate: rc=%d %q", rc, shown)
	}
	writeKeel(t, r, strings.Replace(minimalKeel, `lint: "true"`, `lint: "false"`, 1))
	out, _, rc = run("gate", "extra")
	if rc != 1 || !strings.Contains(out, "gate: extra - FAILED (1 of 1)") {
		t.Fatalf("failing gate: rc=%d out=%q", rc, out)
	}
	if _, _, rc := run("gate", "nope"); rc != cli.ExitUsage {
		t.Fatalf("unknown gate rc=%d", rc)
	}
	if _, _, rc := run("gate"); rc != cli.ExitUsage {
		t.Fatalf("no gate rc=%d", rc)
	}
}

func TestMeasureCommand(t *testing.T) {
	r := repo(t)
	writeKeel(t, r, `version: 1
scripts:
  lint:
    run: "printf 'a.ts:1: m\na.ts:2: m\nb.ts:1: m\n'; exit 1"
    format: errorformat
    pattern: '^(?P<file>[^:]+):(?P<line>\d+): (?P<message>.*)$'
    class: heuristic
  plain: "true"
gates:
  fast: { scripts: [guard, lint] }
  commit: { scripts: [guard, lint], changes: staged }
  slow: { scripts: [guard, lint], changes: branch }
`)
	out, errb, rc := run("measure", "lint")
	if rc != 0 || !strings.HasPrefix(out, "# measured_at: ") || !strings.HasSuffix(out, "a.ts\t2\nb.ts\t1\n") {
		t.Fatalf("rc=%d out=%q err=%q", rc, out, errb)
	}
	if _, errb, rc := run("measure", "plain"); rc != cli.ExitError || !strings.Contains(errb, "no per-file counts") {
		t.Fatalf("plain: rc=%d err=%q", rc, errb)
	}
	if _, _, rc := run("measure", "nope"); rc != cli.ExitUsage {
		t.Fatalf("unknown: rc=%d", rc)
	}
}

func TestGateJSON(t *testing.T) {
	r := repo(t)
	writeKeel(t, r, minimalKeel)
	out, _, rc := run("gate", "extra", "--json")
	var g map[string]any
	if rc != 0 || json.Unmarshal([]byte(out), &g) != nil {
		t.Fatalf("rc=%d out=%q", rc, out)
	}
	if g["gate"] != "extra" || g["status"] != "pass" || len(g["scripts"].([]any)) != 1 {
		t.Fatalf("gate json = %v", g)
	}
}

func TestValidateFullExampleWithRealBuiltins(t *testing.T) {
	b, err := os.ReadFile("../config/testdata/valid/full.yml") // before repo() changes directory
	if err != nil {
		t.Fatal(err)
	}
	r := repo(t)
	writeKeel(t, r, string(b))
	if out, errb, rc := run("validate"); rc != 0 || out != "" || errb != "" {
		t.Fatalf("rc=%d out=%q err=%q", rc, out, errb)
	}
}

func TestGuardCommand(t *testing.T) {
	r := repo(t)
	writeKeel(t, r, minimalKeel)
	// no commit yet: nothing to loosen, the harness is installed in this change (a skip would fail the gate)
	out, _, rc := run("guard")
	if rc != 0 || !strings.Contains(out, "no base commit yet: the harness is installed in this change") {
		t.Fatalf("unborn: rc=%d out=%q", rc, out)
	}
	if _, _, rc := run("guard", "--bogus"); rc != cli.ExitUsage {
		t.Fatalf("bad flag rc=%d", rc)
	}
}

func runWithStdin(stdin string, args ...string) (string, string, int) {
	old := cli.Stdin
	cli.Stdin = strings.NewReader(stdin)
	defer func() { cli.Stdin = old }()
	return run(args...)
}

func writePayload(root, file, mode string) string {
	return `{"hook_event_name":"PreToolUse","tool_name":"Write","cwd":"` + root + `","permission_mode":"` + mode + `","tool_input":{"file_path":"` + file + `"}}`
}

func TestHookPreToolUseCLI(t *testing.T) {
	r := repo(t)
	writeKeel(t, r, minimalKeel)
	out, errb, rc := runWithStdin(writePayload(r, r+"/.agents/keel.yml", "default"), "hook", "pre-tool-use")
	var got map[string]any
	if rc != 0 || json.Unmarshal([]byte(out), &got) != nil || got["permissionDecision"] != "ask" || got["hookSpecificOutput"] == nil {
		t.Fatalf("rc=%d out=%q err=%q", rc, out, errb)
	}
	out, _, rc = runWithStdin(writePayload(r, r+"/.agents/keel.yml", "bypassPermissions"), "hook", "pre-tool-use")
	if rc != 0 || !strings.Contains(out, `"permissionDecision":"deny"`) {
		t.Fatalf("bypass: rc=%d out=%q", rc, out)
	}
	out, _, rc = runWithStdin(writePayload(r, r+"/src/a.go", "default"), "hook", "pre-tool-use")
	if rc != 0 || out != "" {
		t.Fatalf("unprotected path must print nothing: rc=%d out=%q", rc, out)
	}
}

func TestHookFailSafeOnPinMismatch(t *testing.T) {
	r := repo(t)
	writeKeel(t, r, minimalKeel)
	lockText := "version=9.9.9\n"
	for _, p := range []string{"linux-amd64", "linux-arm64", "darwin-amd64", "darwin-arm64"} {
		lockText += p + "=" + strings.Repeat("a", 64) + "\n"
	}
	os.WriteFile(filepath.Join(r, ".agents", "keel.lock"), []byte(lockText), 0o644)
	out, _, rc := runWithStdin(writePayload(r, r+"/src/a.go", "default"), "hook", "pre-tool-use")
	if rc != 0 || !strings.Contains(out, `"permissionDecision":"ask"`) || !strings.Contains(out, "pin mismatch") {
		t.Fatalf("rc=%d out=%q", rc, out)
	}
	out, _, rc = runWithStdin(writePayload(r, r+"/src/a.go", "dontAsk"), "hook", "pre-tool-use")
	if rc != 0 || !strings.Contains(out, `"permissionDecision":"deny"`) {
		t.Fatalf("dontAsk: rc=%d out=%q", rc, out)
	}
	out, _, rc = runWithStdin(`{"hook_event_name":"Stop","cwd":"`+r+`"}`, "hook", "stop")
	if rc != 0 || !strings.Contains(out, "the gates did not run") || strings.Contains(out, `"block"`) {
		t.Fatalf("stop: rc=%d out=%q", rc, out)
	}
}

func TestHookOutsideARepositoryFailsSafe(t *testing.T) {
	d := t.TempDir()
	t.Chdir(d)
	out, _, rc := runWithStdin(`{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"`+d+`","tool_input":{"command":"ls"}}`, "hook", "pre-tool-use")
	if rc != 0 || !strings.Contains(out, `"permissionDecision":"ask"`) {
		t.Fatalf("rc=%d out=%q", rc, out)
	}
	out, _, rc = runWithStdin("not json", "hook", "pre-tool-use")
	if rc != 0 || !strings.Contains(out, `"permissionDecision":"ask"`) {
		t.Fatalf("garbage: rc=%d out=%q", rc, out)
	}
}

func TestHookSetupModeWithoutKeelYml(t *testing.T) {
	d := t.TempDir()
	if out, err := exec.Command("git", "-C", d, "init", "-q", ".").CombinedOutput(); err != nil {
		t.Fatalf("%v %s", err, out)
	}
	t.Chdir(d)
	out, _, rc := runWithStdin(writePayload(d, d+"/AGENTS.md", "default"), "hook", "pre-tool-use", "--setup")
	if rc != 0 || !strings.Contains(out, `"permissionDecision":"ask"`) || strings.Contains(out, "unavailable") {
		t.Fatalf("rc=%d out=%q", rc, out)
	}
}

func TestHookUsage(t *testing.T) {
	for _, args := range [][]string{{"hook"}, {"hook", "bogus"}, {"hook", "stop", "x"}, {"hook", "commit-msg"}, {"hook", "pre-tool-use", "--nope"}} {
		if _, _, rc := run(args...); rc != cli.ExitUsage {
			t.Errorf("%v: rc=%d", args, rc)
		}
	}
}

func TestHookCommitMsgCLI(t *testing.T) {
	r := repo(t)
	writeKeel(t, r, `version: 1
githooks: { pre-commit: commit, commit-msg: cm }
scripts:
  lint: "true"
  cm: { builtin: commit-message, with: { pattern: '^(feat|fix): .+' } }
gates:
  fast: { scripts: [guard, lint] }
  commit: { scripts: [guard, lint], changes: staged }
  slow: { scripts: [guard, lint], changes: branch }
`)
	msg := filepath.Join(r, "MSG")
	os.WriteFile(msg, []byte("feat: ok\n"), 0o644)
	if _, _, rc := run("hook", "commit-msg", msg); rc != 0 {
		t.Fatalf("good message rc=%d", rc)
	}
	os.WriteFile(msg, []byte("wip\n"), 0o644)
	if _, errb, rc := run("hook", "commit-msg", msg); rc != 1 || !strings.Contains(errb, "^(feat|fix): .+") {
		t.Fatalf("bad message rc=%d err=%q", rc, errb)
	}
}

func TestCheckCommand(t *testing.T) {
	r := repo(t)
	writeKeel(t, r, minimalKeel)
	out, errb, rc := run("check")
	if rc != 0 || errb != "" || !strings.Contains(out, "warn hook-missing:") || !strings.Contains(out, "warn run-state:") || !strings.Contains(out, "warn reviewer-missing:") {
		t.Fatalf("rc=%d out=%q err=%q", rc, out, errb)
	}
	if _, _, rc := run("check", "--strict"); rc != cli.ExitFail {
		t.Fatalf("--strict with warnings: rc=%d", rc)
	}
	// pin-mismatch is reported, not enforced
	lockText := "version=9.9.9\n"
	for _, p := range []string{"linux-amd64", "linux-arm64", "darwin-amd64", "darwin-arm64"} {
		lockText += p + "=" + strings.Repeat("a", 64) + "\n"
	}
	os.WriteFile(filepath.Join(r, ".agents", "keel.lock"), []byte(lockText), 0o644)
	out, _, rc = run("check")
	if rc != 0 || !strings.Contains(out, "warn pin-mismatch: pin mismatch: keel.lock pins 9.9.9, this kh is 0.5.0-dev") {
		t.Fatalf("pin: rc=%d out=%q", rc, out)
	}
	writeKeel(t, r, "version: 1\n")
	_, errb, rc = run("check")
	if rc != cli.ExitError || !strings.Contains(errb, `required gate "fast" is missing`) {
		t.Fatalf("invalid: rc=%d err=%q", rc, errb)
	}
	if _, _, rc := run("check", "--nope"); rc != cli.ExitUsage {
		t.Fatalf("usage rc=%d", rc)
	}
}

func TestUnbornRepositoryGatesPass(t *testing.T) {
	r := repo(t)
	writeKeel(t, r, minimalKeel)
	for _, g := range []string{"fast", "commit"} {
		out, errb, rc := run("gate", g)
		if rc != 0 || !strings.Contains(out, "gate: "+g+" - PASSED") {
			t.Fatalf("%s gate in a repository with no commit: rc=%d out=%q err=%q", g, rc, out, errb)
		}
	}
}

func TestSchemaKeelDescribesBuiltinWith(t *testing.T) {
	out, _, rc := run("schema", "keel")
	var doc map[string]any
	if rc != 0 || json.Unmarshal([]byte(out), &doc) != nil {
		t.Fatalf("rc=%d", rc)
	}
	with := doc["$defs"].(map[string]any)["with"].(map[string]any)
	for _, n := range []string{"file-size", "code-language", "test-presence", "folder-layout", "pattern", "architecture-grep", "dependencies", "guard", "memory", "scope", "merge-check", "commit-message", "branch-name"} {
		if with[n] == nil {
			t.Errorf("kh schema keel does not describe the with: block of %s", n)
		}
	}
	if !strings.Contains(out, `"mappings"`) || !strings.Contains(out, "$1") {
		t.Error("the test-presence mapping syntax is not in the schema")
	}
}
