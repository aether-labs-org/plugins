package gate_test

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/config"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/gate"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/render"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/result"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/scope"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/script"
)

func sh(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false"}, args...)...)
	cmd.Dir = dir
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
}

// setup builds a repository with the given scripts block and a gate "g".
func setup(t *testing.T, scripts string, gateScripts []string, ceiling string) (script.Exec, string) {
	t.Helper()
	d, _ := filepath.EvalSymlinks(t.TempDir())
	sh(t, d, "init", "-q", ".")
	yml := "version: 1\nscripts:\n" + scripts + "gates:\n  g: { scripts: [" + strings.Join(gateScripts, ", ") + "]"
	if ceiling != "" {
		yml += ", ceiling: " + ceiling
	}
	yml += " }\n"
	os.MkdirAll(filepath.Join(d, ".agents"), 0o755)
	os.WriteFile(filepath.Join(d, ".agents", "bmax.yml"), []byte(yml), 0o644)
	os.WriteFile(filepath.Join(d, ".gitignore"), []byte(".agents/run/\n"), 0o644)
	sh(t, d, "add", "-A")
	sh(t, d, "commit", "-q", "-m", "seed")
	c, err := config.Parse([]byte(yml))
	if err != nil {
		t.Fatal(err)
	}
	return script.Exec{Root: d, Cfg: c, Changes: scope.Worktree, BmaxVersion: "test"}, d
}

func names(prefix string, n int) []string {
	var out []string
	for i := 0; i < n; i++ {
		out = append(out, fmt.Sprintf("%s%d", prefix, i))
	}
	return out
}

func TestVerdictPassed(t *testing.T) {
	sc := "  a: \"true\"\n  b: \"true\"\n  c: \"true\"\n  d: \"true\"\n  e: { run: \"true\", files: \"*.nomatch\" }\n"
	e, _ := setup(t, sc, []string{"a", "b", "c", "d", "e"}, "")
	r, err := gate.Run(context.Background(), e, "g")
	if err != nil {
		t.Fatal(err)
	}
	line := render.GateVerdict(r)
	if r.Status != result.Pass || r.ExitCode() != 0 || !strings.HasPrefix(line, "gate: g - PASSED (4 of 5, 1 skipped) | spent ") || !strings.HasSuffix(line, " | run "+r.ID) {
		t.Fatalf("status=%s line=%q", r.Status, line)
	}
}

func TestVerdictFailed(t *testing.T) {
	sc := "  a: \"true\"\n  b: \"false\"\n  c: \"true\"\n  d: \"true\"\n  e: \"true\"\n"
	e, _ := setup(t, sc, []string{"a", "b", "c", "d", "e"}, "")
	r, _ := gate.Run(context.Background(), e, "g")
	line := render.GateVerdict(r)
	if r.Status != result.Fail || r.ExitCode() != 1 || !strings.Contains(line, "FAILED (1 of 5)") {
		t.Fatalf("status=%s line=%q", r.Status, line)
	}
	if len(r.Scripts) != 5 {
		t.Errorf("a failing script must not stop the others: %d ran", len(r.Scripts))
	}
}

func TestSecuritySkipFails(t *testing.T) {
	sc := "  a: \"true\"\n  sec: { run: scan, class: security, requires: [definitely-missing-tool] }\n"
	e, _ := setup(t, sc, []string{"a", "sec"}, "")
	r, _ := gate.Run(context.Background(), e, "g")
	if r.Status != result.Fail || r.Scripts[1].Status != result.Skip {
		t.Fatalf("status=%s scripts=%v", r.Status, r.Scripts[1].Status)
	}
	if line := render.GateVerdict(r); !strings.Contains(line, "FAILED (1 of 2)") {
		t.Errorf("line = %q", line)
	}
	// a skipped non-security script does not fail the gate
	sc = "  a: \"true\"\n  h: { run: scan, class: heuristic, requires: [definitely-missing-tool] }\n"
	e, _ = setup(t, sc, []string{"a", "h"}, "")
	if r, _ := gate.Run(context.Background(), e, "g"); r.Status != result.Pass {
		t.Errorf("heuristic skip failed the gate: %s", r.Status)
	}
}

func TestOrderKept(t *testing.T) {
	sc := "  z: \"true\"\n  a: \"true\"\n  m: \"true\"\n"
	e, _ := setup(t, sc, []string{"m", "z", "a"}, "")
	r, _ := gate.Run(context.Background(), e, "g")
	var got []string
	for _, s := range r.Scripts {
		got = append(got, s.Script)
	}
	if strings.Join(got, ",") != "m,z,a" {
		t.Errorf("order = %v", got)
	}
}

func TestCeilingFlagged(t *testing.T) {
	e, _ := setup(t, "  a: \"sleep 0.05\"\n", []string{"a"}, "1ms")
	r, _ := gate.Run(context.Background(), e, "g")
	if !r.OverCeiling || r.Status != result.Pass {
		t.Fatalf("over=%v status=%s", r.OverCeiling, r.Status)
	}
	if line := render.GateVerdict(r); !strings.Contains(line, "ceiling 1ms, spent") || !strings.HasSuffix(line, " | over ceiling") {
		t.Errorf("line = %q", line)
	}
	e, _ = setup(t, "  a: \"true\"\n", []string{"a"}, "10m")
	r, _ = gate.Run(context.Background(), e, "g")
	if line := render.GateVerdict(r); !strings.Contains(line, "ceiling 10m, spent") || r.OverCeiling {
		t.Errorf("line = %q over=%v", line, r.OverCeiling)
	}
}

func TestGateIDListsScripts(t *testing.T) {
	e, d := setup(t, "  a: \"true\"\n  b: \"false\"\n", []string{"a", "b"}, "")
	r, _ := gate.Run(context.Background(), e, "g")
	m, ok := gate.LoadMeta(d, r.ID)
	if !ok || m.Gate != "g" || len(m.Scripts) != 2 || m.Scripts[0] != r.Scripts[0].ID || m.Scripts[1] != r.Scripts[1].ID {
		t.Fatalf("meta = %+v ok=%v", m, ok)
	}
	if r.Scripts[0].Gate != "g" {
		t.Errorf("script result gate = %q", r.Scripts[0].Gate)
	}
	if _, ok := gate.LoadMeta(d, r.Scripts[0].ID); ok {
		t.Error("a script run is not a gate run")
	}
}

func TestUnknownGate(t *testing.T) {
	e, _ := setup(t, "  a: \"true\"\n", []string{"a"}, "")
	if _, err := gate.Run(context.Background(), e, "nope"); err == nil {
		t.Fatal("unknown gate accepted")
	}
}

func TestLockWaitsThenErrors(t *testing.T) {
	e, d := setup(t, "  a: \"true\"\n", []string{"a"}, "")
	holder := exec.Command("sleep", "30")
	if err := holder.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { holder.Process.Kill(); holder.Wait() }()
	os.MkdirAll(filepath.Join(d, ".agents", "run"), 0o700)
	os.WriteFile(filepath.Join(d, ".agents", "run", "gate.lock"), []byte(strconv.Itoa(holder.Process.Pid)+"\n"), 0o600)
	old := gate.LockWait
	gate.LockWait = 300 * time.Millisecond
	defer func() { gate.LockWait = old }()
	start := time.Now()
	_, err := gate.Run(context.Background(), e, "g")
	if err == nil || !strings.Contains(err.Error(), "another gate is running (pid "+strconv.Itoa(holder.Process.Pid)+")") {
		t.Fatalf("err = %v", err)
	}
	if time.Since(start) < 250*time.Millisecond {
		t.Errorf("did not wait: %v", time.Since(start))
	}
}

func TestStaleLockTakenOver(t *testing.T) {
	e, d := setup(t, "  a: \"true\"\n", []string{"a"}, "")
	dead := exec.Command("true")
	dead.Run() // exits; its pid is now dead
	os.MkdirAll(filepath.Join(d, ".agents", "run"), 0o700)
	lock := filepath.Join(d, ".agents", "run", "gate.lock")
	os.WriteFile(lock, []byte(strconv.Itoa(dead.Process.Pid)+"\n"), 0o600)
	r, err := gate.Run(context.Background(), e, "g")
	if err != nil || r.Status != result.Pass {
		t.Fatalf("err=%v status=%s", err, r.Status)
	}
	if _, err := os.Stat(lock); err == nil {
		t.Error("lock not released")
	}
}

func TestLockReleasedAfterRun(t *testing.T) {
	e, d := setup(t, "  a: \"false\"\n", []string{"a"}, "")
	gate.Run(context.Background(), e, "g")
	if _, err := os.Stat(filepath.Join(d, ".agents", "run", "gate.lock")); err == nil {
		t.Error("lock left behind")
	}
}

func TestOutputCap(t *testing.T) {
	var sc strings.Builder
	ids := names("f", 12)
	for _, id := range ids {
		fmt.Fprintf(&sc, "  %s: \"echo error: boom %s; echo line2; echo line3; false\"\n", id, id)
	}
	e, _ := setup(t, sc.String(), ids, "")
	r, _ := gate.Run(context.Background(), e, "g")
	text := render.Gate(r)
	lines := strings.Split(strings.TrimRight(text, "\n"), "\n")
	if len(lines) > 40 {
		t.Fatalf("%d lines", len(lines))
	}
	if !strings.Contains(text, "… output capped at 40 lines - bmax show "+r.ID) {
		t.Errorf("cap line missing:\n%s", text)
	}
	if !strings.HasPrefix(lines[len(lines)-1], "gate: g - FAILED (12 of 12)") {
		t.Errorf("verdict not last: %q", lines[len(lines)-1])
	}
}

func TestSmallGateNotCapped(t *testing.T) {
	e, _ := setup(t, "  a: \"true\"\n  b: \"echo error: x; false\"\n", []string{"a", "b"}, "")
	r, _ := gate.Run(context.Background(), e, "g")
	text := render.Gate(r)
	if strings.Contains(text, "capped") || !strings.Contains(text, "a  PASS") || !strings.Contains(text, "b  FAIL") {
		t.Errorf("text:\n%s", text)
	}
}
