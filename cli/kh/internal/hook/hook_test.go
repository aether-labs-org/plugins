package hook

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/aether-labs-org/plugins/cli/kh/internal/builtin"
	"github.com/aether-labs-org/plugins/cli/kh/internal/config"
)

const keelYML = `version: 1
guides: [AGENTS.md, docs/review.md]
githooks: { mode: native, pre-commit: commit, pre-push: slow, commit-msg: commit-message }
scripts:
  test: { run: "./gradlew test" }
  check: { run: "test ! -e FAIL" }
  commit-message: { builtin: commit-message, with: { pattern: '^(feat|fix): .+' } }
gates:
  fast: { scripts: [guard, check] }
  commit: { scripts: [guard, check], changes: staged }
  slow: { scripts: [guard, check], changes: branch }
`

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

// project: a committed repository with a harness.
func project(t *testing.T) (string, *config.Config) {
	t.Helper()
	d, _ := filepath.EvalSymlinks(t.TempDir())
	t.Setenv("KEEL_GUARD_BASE", "")
	t.Setenv("HOME", filepath.Join(d, "home"))
	git(t, d, "init", "-q", ".")
	write(t, d, ".agents/keel.yml", keelYML)
	write(t, d, ".gitignore", ".agents/run/\nhome/\n")
	write(t, d, "AGENTS.md", "# a\n")
	write(t, d, "docs/review.md", "# r\n")
	write(t, d, "docs/adr/My ADR.md", "# adr\nStatus: accepted\n")
	write(t, d, "src/main.go", "package main\n")
	git(t, d, "add", "-A")
	git(t, d, "commit", "-q", "-m", "seed")
	cfg, err := config.LoadValid(d, builtin.Default().Validator())
	if err != nil {
		t.Fatalf("config: %v", err)
	}
	return d, cfg
}

// payload loads a fixture and puts the root in.
func payload(t *testing.T, name, root string) Payload {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("..", "..", "testdata", "hooks", name))
	if err != nil {
		t.Fatal(err)
	}
	p, err := Parse(strings.NewReader(strings.ReplaceAll(string(b), "__ROOT__", root)))
	if err != nil {
		t.Fatalf("%s: %v", name, err)
	}
	return p
}

func TestParseShapes(t *testing.T) {
	p := payload(t, "claude/write-agents-md.json", "/r")
	if p.Event != "PreToolUse" || p.Tool != "Write" || p.FilePath != "/r/AGENTS.md" || p.PermissionMode != "default" || p.Cwd != "/r" {
		t.Errorf("claude: %+v", p)
	}
	p = payload(t, "claude/notebook-edit.json", "/r")
	if p.Tool != "NotebookEdit" || p.FilePath != "/r/docs/review.md" {
		t.Errorf("notebook: %+v", p)
	}
	p = payload(t, "claude/bash-gradlew.json", "/r")
	if p.Tool != "Bash" || p.Command != "cd app && ./gradlew test | tail -20" || p.FilePath != "" {
		t.Errorf("bash: %+v", p)
	}
	p = payload(t, "claude/stop-active.json", "/r")
	if p.Event != "Stop" || !p.StopHookActive {
		t.Errorf("stop: %+v", p)
	}
	p = payload(t, "copilot/write-agents-md.json", "/r")
	if p.Tool != "Write" || p.FilePath != "/r/AGENTS.md" {
		t.Errorf("copilot claude-format: %+v", p)
	}
	p = payload(t, "copilot/native-create-agents-md.json", "/r")
	if p.Tool != "Write" || p.FilePath != "/r/AGENTS.md" {
		t.Errorf("copilot native create: %+v", p)
	}
	p = payload(t, "copilot/native-bash-redirect.json", "/r")
	if p.Tool != "Bash" || p.Command != "echo x > AGENTS.md" {
		t.Errorf("copilot native bash: %+v", p)
	}
	if _, err := Parse(strings.NewReader("not json")); err == nil {
		t.Error("garbage accepted")
	}
}

func TestProtectedWriteAsks(t *testing.T) {
	d, cfg := project(t)
	for _, f := range []string{"claude/write-agents-md.json", "copilot/write-agents-md.json", "copilot/native-create-agents-md.json"} {
		dec := PreToolUse(d, cfg, payload(t, f, d), false)
		if dec.Kind != "ask" || !strings.Contains(dec.Reason, "AGENTS.md") || !strings.Contains(dec.Reason, "guides") {
			t.Errorf("%s: %+v", f, dec)
		}
	}
	// relative path, MultiEdit on an ADR with a space, dotdot, the review checklist via NotebookEdit
	for _, f := range []string{"claude/edit-keel-yml-relative.json", "claude/multiedit-adr.json", "claude/write-dotdot.json", "claude/notebook-edit.json"} {
		if dec := PreToolUse(d, cfg, payload(t, f, d), false); dec.Kind != "ask" {
			t.Errorf("%s: %+v", f, dec)
		}
	}
	if dec := PreToolUse(d, cfg, payload(t, "claude/write-source.json", d), false); dec.Kind != "allow" {
		t.Errorf("source file: %+v", dec)
	}
}

func TestNotebookPathParsed(t *testing.T) {
	d, cfg := project(t)
	dec := PreToolUse(d, cfg, payload(t, "claude/notebook-edit.json", d), false)
	if dec.Kind != "ask" || !strings.Contains(dec.Reason, "docs/review.md") {
		t.Errorf("%+v", dec)
	}
}

func TestSymlinkToProtectedFileAsks(t *testing.T) {
	d, cfg := project(t)
	os.Symlink(filepath.Join(d, ".agents/keel.yml"), filepath.Join(d, "link.yml"))
	p := Payload{Event: "PreToolUse", Tool: "Write", FilePath: filepath.Join(d, "link.yml"), Cwd: d}
	if dec := PreToolUse(d, cfg, p, false); dec.Kind != "ask" {
		t.Errorf("%+v", dec)
	}
}

func TestBypassDenies(t *testing.T) {
	d, cfg := project(t)
	for _, f := range []string{"claude/write-agents-md-bypass.json", "claude/write-agents-md-dontask.json"} {
		dec := PreToolUse(d, cfg, payload(t, f, d), false)
		if dec.Kind != "deny" || !strings.Contains(dec.Reason, "switch mode") {
			t.Errorf("%s: %+v", f, dec)
		}
	}
}

func TestShellWriteDenied(t *testing.T) {
	d, cfg := project(t)
	for _, f := range []string{"claude/bash-redirect-keel.json", "claude/bash-sed-keel.json", "copilot/native-bash-redirect.json"} {
		dec := PreToolUse(d, cfg, payload(t, f, d), false)
		if dec.Kind != "deny" || !strings.Contains(dec.Reason, "protected") {
			t.Errorf("%s: %+v", f, dec)
		}
	}
}

func TestP1Reproduction(t *testing.T) {
	d, cfg := project(t)
	dec := PreToolUse(d, cfg, payload(t, "claude/bash-sed-keel.json", d), false)
	if dec.Kind != "deny" {
		t.Fatalf("shell edit of keel.yml removing guard: %+v", dec)
	}
	// and if the edit lands anyway, kh validate fails
	b, _ := os.ReadFile(filepath.Join(d, ".agents/keel.yml"))
	write(t, d, ".agents/keel.yml", strings.ReplaceAll(string(b), "[guard, check]", "[check]"))
	if _, err := config.LoadValid(d, builtin.Default().Validator()); err == nil || !strings.Contains(err.Error(), "must list guard") {
		t.Fatalf("validate after the edit: %v", err)
	}
}

func TestShellWriteTricks(t *testing.T) {
	d, cfg := project(t)
	cmds := []string{
		"cd docs && echo x > review.md",
		`python3 -c "open('AGENTS.md','w').write('x')"`,
		"cp /tmp/x .agents/keel.lock",
		"rm -rf .agents/baselines",
		"rm -rf docs/adr",
		"mv AGENTS.md /tmp/gone",
		`bash -c 'echo hi >> AGENTS.md'`,
		"git checkout -- AGENTS.md",
		"tee docs/review.md < /dev/null",
		"ln -sf /tmp/x docs/adr/0001.md",
	}
	for _, c := range cmds {
		p := Payload{Tool: "Bash", Command: c, Cwd: d}
		if dec := PreToolUse(d, cfg, p, false); dec.Kind != "deny" {
			t.Errorf("%q: %+v", c, dec)
		}
	}
	allowed := []string{"cat AGENTS.md", "ls docs", "echo hi > src/out.txt", "cp AGENTS.md /tmp/copy", "rm -f src/old.go", "cd docs && ls", "git status"}
	for _, c := range allowed {
		p := Payload{Tool: "Bash", Command: c, Cwd: d}
		if dec := PreToolUse(d, cfg, p, false); dec.Kind != "allow" {
			t.Errorf("%q: %+v", c, dec)
		}
	}
}

func TestShellGitApplyReadsThePatch(t *testing.T) {
	d, cfg := project(t)
	write(t, d, "fix.patch", "--- a/AGENTS.md\n+++ b/AGENTS.md\n@@ -1 +1 @@\n-# a\n+# b\n")
	if dec := PreToolUse(d, cfg, Payload{Tool: "Bash", Command: "git apply fix.patch", Cwd: d}, false); dec.Kind != "deny" {
		t.Errorf("%+v", dec)
	}
	write(t, d, "ok.patch", "--- a/src/main.go\n+++ b/src/main.go\n@@ -1 +1 @@\n-x\n+y\n")
	if dec := PreToolUse(d, cfg, Payload{Tool: "Bash", Command: "git apply ok.patch", Cwd: d}, false); dec.Kind != "allow" {
		t.Errorf("%+v", dec)
	}
}

func TestForbiddenDenied(t *testing.T) {
	d, cfg := project(t)
	dec := PreToolUse(d, cfg, payload(t, "claude/bash-no-verify.json", d), false)
	if dec.Kind != "deny" || !strings.Contains(dec.Reason, "--no-verify") {
		t.Errorf("%+v", dec)
	}
}

func TestInterception(t *testing.T) {
	d, cfg := project(t)
	dec := PreToolUse(d, cfg, payload(t, "claude/bash-gradlew.json", d), false)
	if dec.Kind != "deny" || !strings.Contains(dec.Reason, "kh run test") || !strings.Contains(dec.Reason, "do not pipe its output") {
		t.Errorf("%+v", dec)
	}
	// the escape hatch and a launcher in another segment
	for _, c := range []string{"sh .agents/bin/kh run -- ./gradlew test", "sh .agents/bin/kh run test"} {
		if dec := PreToolUse(d, cfg, Payload{Tool: "Bash", Command: c, Cwd: d}, false); dec.Kind != "allow" {
			t.Errorf("%q: %+v", c, dec)
		}
	}
	// setup mode does not intercept
	if dec := PreToolUse(d, cfg, payload(t, "claude/bash-gradlew.json", d), true); dec.Kind != "allow" {
		t.Errorf("setup: %+v", dec)
	}
}

func TestUndeclaredAllowed(t *testing.T) {
	d, cfg := project(t)
	for _, f := range []string{"claude/bash-make-foo.json", "claude/bash-ls.json"} {
		if dec := PreToolUse(d, cfg, payload(t, f, d), false); dec.Kind != "allow" {
			t.Errorf("%s: %+v", f, dec)
		}
	}
}

func TestUnsplittableAllowed(t *testing.T) {
	d, cfg := project(t)
	if dec := PreToolUse(d, cfg, payload(t, "claude/bash-unbalanced.json", d), false); dec.Kind != "allow" {
		t.Errorf("%+v", dec)
	}
	// unsplittable, but an explicit positive in the part that parsed is still denied (ruling)
	p := Payload{Tool: "Bash", Command: "git commit --no-verify -m 'unbalanced", Cwd: d}
	if dec := PreToolUse(d, cfg, p, false); dec.Kind != "deny" {
		t.Errorf("%+v", dec)
	}
	// unsplittable commands are not intercepted
	p = Payload{Tool: "Bash", Command: "./gradlew test 'unbalanced", Cwd: d}
	if dec := PreToolUse(d, cfg, p, false); dec.Kind != "allow" {
		t.Errorf("%+v", dec)
	}
}

func TestSetupModeWithoutKeelYml(t *testing.T) {
	d, _ := filepath.EvalSymlinks(t.TempDir())
	t.Setenv("HOME", filepath.Join(d, "home"))
	git(t, d, "init", "-q", ".")
	for _, f := range []string{"claude/write-agents-md.json", "copilot/write-agents-md.json"} {
		if dec := PreToolUse(d, nil, payload(t, f, d), true); dec.Kind != "ask" {
			t.Errorf("%s: %+v", f, dec)
		}
	}
	if dec := PreToolUse(d, nil, payload(t, "claude/write-source.json", d), true); dec.Kind != "allow" {
		t.Errorf("source: %+v", dec)
	}
	if dec := PreToolUse(d, nil, Payload{Tool: "Write", FilePath: filepath.Join(d, ".agents/skills/x/SKILL.md"), Cwd: d}, true); dec.Kind != "allow" {
		t.Errorf("skills dir is not ours: %+v", dec)
	}
	if dec := PreToolUse(d, nil, payload(t, "claude/write-agents-md-bypass.json", d), true); dec.Kind != "deny" {
		t.Errorf("setup + bypass: %+v", dec)
	}
}

func TestOutputDualShape(t *testing.T) {
	var buf bytes.Buffer
	WritePreToolUse(&buf, Decision{"ask", "because"})
	var got map[string]any
	if err := json.Unmarshal(buf.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	hs := got["hookSpecificOutput"].(map[string]any)
	if hs["hookEventName"] != "PreToolUse" || hs["permissionDecision"] != "ask" || hs["permissionDecisionReason"] != "because" ||
		got["permissionDecision"] != "ask" || got["permissionDecisionReason"] != "because" {
		t.Errorf("shape: %s", buf.String())
	}
	buf.Reset()
	WritePreToolUse(&buf, Decision{Kind: "allow"})
	if buf.Len() != 0 {
		t.Errorf("allow prints %q", buf.String())
	}
}

func TestFailSafe(t *testing.T) {
	read := func(mode string) string {
		return `{"hook_event_name":"PreToolUse","tool_name":"Write","permission_mode":"` + mode + `","tool_input":{"file_path":"/x"}}`
	}
	var buf bytes.Buffer
	FailSafe("pre-tool-use", strings.NewReader(read("default")), &buf, "pin mismatch: keel.lock pins 0.5.0, this kh is 0.5.1")
	var got map[string]any
	json.Unmarshal(buf.Bytes(), &got)
	if got["permissionDecision"] != "ask" || !strings.Contains(got["permissionDecisionReason"].(string), "pin mismatch") || got["hookSpecificOutput"] == nil {
		t.Errorf("ask: %s", buf.String())
	}
	for _, mode := range []string{"bypassPermissions", "dontAsk"} {
		buf.Reset()
		FailSafe("pre-tool-use", strings.NewReader(read(mode)), &buf, "x")
		json.Unmarshal(buf.Bytes(), &got)
		if got["permissionDecision"] != "deny" {
			t.Errorf("%s: %s", mode, buf.String())
		}
	}
	buf.Reset()
	FailSafe("pre-tool-use", strings.NewReader("garbage"), &buf, "x")
	json.Unmarshal(buf.Bytes(), &got)
	if got["permissionDecision"] != "ask" {
		t.Errorf("garbage stdin: %s", buf.String())
	}
	buf.Reset()
	FailSafe("stop", strings.NewReader("{}"), &buf, "run sh .agents/bin/kh setup")
	json.Unmarshal(buf.Bytes(), &got)
	if _, blocks := got["decision"]; blocks || !strings.Contains(got["systemMessage"].(string), "the gates did not run") {
		t.Errorf("stop: %s", buf.String())
	}
}

// ---------------------------------------------------------------- stop

func runStop(t *testing.T, d string, active bool) (stdout, stderr string) {
	t.Helper()
	var out, errb bytes.Buffer
	if rc := Stop(context.Background(), d, Payload{Event: "Stop", Cwd: d, StopHookActive: active}, &out, &errb); rc != 0 {
		t.Fatalf("Stop returned %d", rc)
	}
	return out.String(), errb.String()
}

func TestStopSilentOnGreenUnchanged(t *testing.T) {
	d, _ := project(t)
	if out, _ := runStop(t, d, false); out != "" {
		t.Fatalf("first green run: %q", out)
	}
	// the gate would fail now, but the tree has not changed since the green run: not even run
	st := loadState(d)
	if st.Green == "" {
		t.Fatal("green state not stored")
	}
	if out, _ := runStop(t, d, false); out != "" {
		t.Fatalf("unchanged tree: %q", out)
	}
	// a new run directory proves nothing ran: count gates
	runs, _ := os.ReadDir(filepath.Join(d, ".agents/run/runs"))
	n := len(runs)
	runStop(t, d, false)
	runs2, _ := os.ReadDir(filepath.Join(d, ".agents/run/runs"))
	if len(runs2) != n {
		t.Errorf("an unchanged tree ran the gate again (%d -> %d runs)", n, len(runs2))
	}
}

func TestStopBlocksOnce(t *testing.T) {
	d, _ := project(t)
	write(t, d, "FAIL", "x")
	out, _ := runStop(t, d, false)
	var got map[string]any
	if err := json.Unmarshal([]byte(out), &got); err != nil || got["decision"] != "block" || !strings.Contains(got["reason"].(string), "gate: fast - FAILED") {
		t.Fatalf("first failing stop: %q", out)
	}
	out, errb := runStop(t, d, true)
	got = nil
	json.Unmarshal([]byte(out), &got)
	if _, blocks := got["decision"]; blocks || !strings.Contains(got["systemMessage"].(string), "the agent stopped with this failure") {
		t.Fatalf("same failure relayed again: %q", out)
	}
	if !strings.Contains(errb, "the agent stopped with this failure") {
		t.Errorf("stderr = %q", errb)
	}
}

func TestStopNewFailureBlocksAgain(t *testing.T) {
	d, _ := project(t)
	write(t, d, "FAIL", "x")
	runStop(t, d, false)
	// a different failure: another script fails too
	y := strings.Replace(keelYML, "scripts:\n  test:", "scripts:\n  other: { run: \"false\" }\n  test:", 1)
	y = strings.Replace(y, "fast: { scripts: [guard, check] }", "fast: { scripts: [guard, check, other] }", 1)
	write(t, d, ".agents/keel.yml", y)
	out, _ := runStop(t, d, true)
	var got map[string]any
	json.Unmarshal([]byte(out), &got)
	if got["decision"] != "block" {
		t.Fatalf("a new failure with stop_hook_active must block again: %q", out)
	}
}

func TestStopRecoversAfterFix(t *testing.T) {
	d, _ := project(t)
	write(t, d, "FAIL", "x")
	runStop(t, d, false)
	os.Remove(filepath.Join(d, "FAIL"))
	if out, _ := runStop(t, d, false); out != "" {
		t.Fatalf("fixed: %q", out)
	}
	if loadState(d).Green == "" {
		t.Error("green not stored after the fix")
	}
}

func TestStopInvalidConfigNeverBlocks(t *testing.T) {
	d, _ := project(t)
	write(t, d, ".agents/keel.yml", "version: 2\nbogus: true\n")
	out, _ := runStop(t, d, false)
	var got map[string]any
	json.Unmarshal([]byte(out), &got)
	if _, blocks := got["decision"]; blocks || got["systemMessage"] == nil {
		t.Fatalf("%q", out)
	}
}

func TestStopSecuritySkipBlocks(t *testing.T) {
	d, _ := project(t)
	b, _ := os.ReadFile(filepath.Join(d, ".agents/keel.yml"))
	y := strings.Replace(string(b), "  check:", "  sec: { run: scan, class: security, requires: [definitely-missing-tool] }\n  check:", 1)
	y = strings.Replace(y, "fast: { scripts: [guard, check] }", "fast: { scripts: [guard, check, sec] }", 1)
	write(t, d, ".agents/keel.yml", y)
	git(t, d, "add", "-A")
	git(t, d, "commit", "-q", "-m", "sec")
	out, _ := runStop(t, d, false)
	var got map[string]any
	json.Unmarshal([]byte(out), &got)
	if got["decision"] != "block" || !strings.Contains(got["reason"].(string), "definitely-missing-tool not found") {
		t.Fatalf("%q", out)
	}
}

// ---------------------------------------------------------------- commit-msg

func TestCommitMsg(t *testing.T) {
	d, _ := project(t)
	msg := filepath.Join(d, "COMMIT_EDITMSG")
	run := func(body string) (int, string) {
		os.WriteFile(msg, []byte(body), 0o644)
		var errb bytes.Buffer
		rc := CommitMsg(context.Background(), d, msg, &errb)
		return rc, errb.String()
	}
	if rc, _ := run("feat: add a thing\n\nbody\n"); rc != 0 {
		t.Errorf("feat: rc=%d", rc)
	}
	if rc, _ := run("fix: x\n"); rc != 0 {
		t.Errorf("fix: rc=%d", rc)
	}
	rc, errb := run("wip\n")
	if rc != 1 || !strings.Contains(errb, "^(feat|fix): .+") || !strings.Contains(errb, `"wip"`) {
		t.Errorf("wip: rc=%d stderr=%q", rc, errb)
	}
	// not adopted: no githooks.commit-msg
	b, _ := os.ReadFile(filepath.Join(d, ".agents/keel.yml"))
	write(t, d, ".agents/keel.yml", strings.Replace(string(b), ", commit-msg: commit-message", "", 1))
	if rc, _ := run("wip\n"); rc != 0 {
		t.Errorf("not adopted: rc=%d", rc)
	}
	// invalid config
	write(t, d, ".agents/keel.yml", "version: 9\n")
	if rc, errb := run("feat: x\n"); rc != 1 || !strings.Contains(errb, "commit-msg") {
		t.Errorf("invalid config: rc=%d %q", rc, errb)
	}
}

// ------------------------------------------------------- validation round 1

func TestHomeExpansionDeniesUserLevelWrites(t *testing.T) {
	d, cfg := project(t)
	home, _ := filepath.EvalSymlinks(t.TempDir())
	t.Setenv("HOME", home)
	for _, c := range []string{
		"echo x > ~/.claude/settings.json",
		"echo x > $HOME/.claude/settings.json",
		`echo x > "${HOME}/.claude/settings.json"`,
		`tee "$HOME/.copilot/settings.json"`,
		"cp /tmp/x ~/.claude/settings.local.json",
	} {
		if dec := PreToolUse(d, cfg, Payload{Tool: "Bash", Command: c, Cwd: d}, false); dec.Kind != "deny" {
			t.Errorf("%q: %+v", c, dec)
		}
	}
	for _, c := range []string{"echo x > '$HOME/.claude/settings.json'", "echo x > ~/notes.txt", "cat ~/.claude/settings.json"} {
		if dec := PreToolUse(d, cfg, Payload{Tool: "Bash", Command: c, Cwd: d}, false); dec.Kind != "allow" {
			t.Errorf("%q should be allowed: %+v", c, dec)
		}
	}
}

func TestGitAbbreviationsAndEnvironmentDenied(t *testing.T) {
	d, cfg := project(t)
	for _, c := range []string{
		"git commit --no-verif -m x",
		"git push --no-veri",
		"git --config-env=core.hooksPath=V commit -m x",
		"GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null git commit -m x",
		"export GIT_CONFIG_KEY_0=core.hooksPath",
	} {
		if dec := PreToolUse(d, cfg, Payload{Tool: "Bash", Command: c, Cwd: d}, false); dec.Kind != "deny" {
			t.Errorf("%q: %+v", c, dec)
		}
	}
	for _, c := range []string{"git config core.hooksPath", "git config --get core.hooksPath", "git config --get-all core.hooksPath"} {
		if dec := PreToolUse(d, cfg, Payload{Tool: "Bash", Command: c, Cwd: d}, false); dec.Kind != "allow" {
			t.Errorf("%q should be allowed: %+v", c, dec)
		}
	}
}

func TestLauncherPrefixesDenied(t *testing.T) {
	d, cfg := project(t)
	for _, c := range []string{
		"sudo tee AGENTS.md",
		`nohup sh -c "echo > AGENTS.md"`,
		`timeout 5 sh -c 'echo > AGENTS.md'`,
		"nice -n 5 cp /tmp/x .agents/keel.yml",
		"command cp /tmp/x .agents/keel.yml",
		"sudo git commit --no-verify -m x",
		"time tee docs/review.md",
	} {
		if dec := PreToolUse(d, cfg, Payload{Tool: "Bash", Command: c, Cwd: d}, false); dec.Kind != "deny" {
			t.Errorf("%q: %+v", c, dec)
		}
	}
	if dec := PreToolUse(d, cfg, Payload{Tool: "Bash", Command: "sudo ls -la", Cwd: d}, false); dec.Kind != "allow" {
		t.Errorf("sudo ls: %+v", dec)
	}
}

func TestRsyncAndRecursiveCopiesDenied(t *testing.T) {
	d, cfg := project(t)
	for _, c := range []string{"rsync /tmp/x AGENTS.md", "cp -r /tmp/x/. .agents/", "rsync -a /tmp/x/ .agents/", "cp -a /tmp/x docs/adr"} {
		if dec := PreToolUse(d, cfg, Payload{Tool: "Bash", Command: c, Cwd: d}, false); dec.Kind != "deny" {
			t.Errorf("%q: %+v", c, dec)
		}
	}
	// a plain copy into .agents writes .agents/x, which is not protected outside setup mode
	for _, c := range []string{"cp /tmp/x .agents", "rsync /tmp/x src/"} {
		if dec := PreToolUse(d, cfg, Payload{Tool: "Bash", Command: c, Cwd: d}, false); dec.Kind != "allow" {
			t.Errorf("%q should be allowed: %+v", c, dec)
		}
	}
}

func TestInterceptionThroughJSLaunchers(t *testing.T) {
	d, _ := project(t)
	y := strings.Replace(keelYML, `test: { run: "./gradlew test" }`, `test: { run: "npx vitest run --reporter=junit" }`, 1)
	write(t, d, ".agents/keel.yml", y)
	cfg, err := config.LoadValid(d, builtin.Default().Validator())
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range []string{"pnpm vitest run", "pnpm exec vitest", "pnpm dlx vitest", "yarn vitest", "yarn exec vitest", "bunx vitest", "bun x vitest", "npm exec vitest", "npx vitest", "./node_modules/.bin/vitest run", "sudo pnpm vitest"} {
		dec := PreToolUse(d, cfg, Payload{Tool: "Bash", Command: c, Cwd: d}, false)
		if dec.Kind != "deny" || !strings.Contains(dec.Reason, "kh run test") {
			t.Errorf("%q: %+v", c, dec)
		}
	}
	for _, c := range []string{"npm run lint", "npm test", "pnpm run lint", "pnpm test", "yarn run lint", "pnpm install", "npx prettier --check ."} {
		if dec := PreToolUse(d, cfg, Payload{Tool: "Bash", Command: c, Cwd: d}, false); dec.Kind != "allow" {
			t.Errorf("%q should be allowed: %+v", c, dec)
		}
	}
}

// ------------------------------------------------------- validation round 2

func TestStopSameFailureOnANewTurnDoesNotBlockAgain(t *testing.T) {
	d, _ := project(t)
	write(t, d, "FAIL", "x")
	out, _ := runStop(t, d, false)
	var got map[string]any
	json.Unmarshal([]byte(out), &got)
	if got["decision"] != "block" {
		t.Fatalf("first: %q", out)
	}
	// three more user turns with the identical failure: stop_hook_active is false at the start of each
	for i := 0; i < 3; i++ {
		out, errb := runStop(t, d, false)
		got = nil
		json.Unmarshal([]byte(out), &got)
		if _, blocks := got["decision"]; blocks || !strings.Contains(got["systemMessage"].(string), "the agent stopped with this failure") {
			t.Fatalf("turn %d: the same failure was relayed again: %q", i+2, out)
		}
		if !strings.Contains(errb, "the agent stopped with this failure") {
			t.Errorf("stderr = %q", errb)
		}
		if st := loadState(d); st.Green != "" || st.Relayed == "" {
			t.Errorf("state after the message path: %+v (not green, failure remembered)", st)
		}
	}
}

func TestStopNewFailureBlocksOnANewTurn(t *testing.T) {
	d, _ := project(t)
	write(t, d, "FAIL", "x")
	runStop(t, d, false)
	y := strings.Replace(keelYML, "scripts:\n  test:", "scripts:\n  other: { run: \"false\" }\n  test:", 1)
	y = strings.Replace(y, "fast: { scripts: [guard, check] }", "fast: { scripts: [guard, check, other] }", 1)
	write(t, d, ".agents/keel.yml", y)
	out, _ := runStop(t, d, false)
	var got map[string]any
	json.Unmarshal([]byte(out), &got)
	if got["decision"] != "block" {
		t.Fatalf("a different failure must block: %q", out)
	}
}

func TestStopFailureAfterGreenBlocksAgain(t *testing.T) {
	d, _ := project(t)
	write(t, d, "FAIL", "x")
	runStop(t, d, false) // blocks, remembers the failure
	os.Remove(filepath.Join(d, "FAIL"))
	if out, _ := runStop(t, d, false); out != "" {
		t.Fatalf("green: %q", out)
	}
	st := loadState(d)
	if st.Green == "" || st.Relayed != "" {
		t.Fatalf("green must store the tree and forget the relayed failure: %+v", st)
	}
	write(t, d, "FAIL", "x") // the very same failure comes back after a green
	out, _ := runStop(t, d, false)
	var got map[string]any
	json.Unmarshal([]byte(out), &got)
	if got["decision"] != "block" {
		t.Fatalf("a failure after a green is a new occurrence: %q", out)
	}
}

// ------------------------------------------------------- validation round 3

// asking a declared tool for its version or help is not running it: interception lets it through
func TestInterceptionSkipsVersionAndHelp(t *testing.T) {
	d, _ := project(t)
	y := strings.Replace(keelYML, `test: { run: "./gradlew test" }`, `test: { run: "gitleaks detect --no-git --report-path {report}" }
  typecheck: { run: "npx tsc --noEmit" }`, 1)
	y = strings.Replace(y, "fast: { scripts: [guard, check] }", "fast: { scripts: [guard, check, typecheck] }", 1)
	write(t, d, ".agents/keel.yml", y)
	cfg, err := config.LoadValid(d, builtin.Default().Validator())
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range []string{"gitleaks version", "gitleaks dir --help", "gitleaks detect --help", "gitleaks -h", "npx tsc --version", "tsc --version", "gitleaks help detect", "gitleaks --version"} {
		if dec := PreToolUse(d, cfg, Payload{Tool: "Bash", Command: c, Cwd: d}, false); dec.Kind != "allow" {
			t.Errorf("%q should be allowed: %+v", c, dec)
		}
	}
	for _, c := range []string{"gitleaks detect --no-git", "gitleaks detect --no-git --report-path x", "npx tsc --noEmit", "npx tsc -p tsconfig.json"} {
		if dec := PreToolUse(d, cfg, Payload{Tool: "Bash", Command: c, Cwd: d}, false); dec.Kind != "deny" {
			t.Errorf("%q should still be denied: %+v", c, dec)
		}
	}
}
