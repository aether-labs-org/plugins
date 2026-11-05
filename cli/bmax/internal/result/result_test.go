package result_test

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/result"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/run"
)

func ip(n int) *int { return &n }

func TestClassify(t *testing.T) {
	cases := []struct {
		name    string
		o       run.Outcome
		argv0   string
		timeout time.Duration
		status  result.Status
		summary string
		code    *int
	}{
		{"not found", run.Outcome{NotFound: true, ExitCode: -1}, "gradle", time.Minute, result.Skip, "gradle not found - install it (see AGENTS.md)", nil},
		{"start error", run.Outcome{StartErr: errString("boom"), ExitCode: -1}, "x", time.Minute, result.Error, "cannot start: boom", nil},
		{"timeout", run.Outcome{TimedOut: true, ExitCode: 137}, "x", 10 * time.Minute, result.Error, "timed out after 10m0s", nil},
		{"timeout short", run.Outcome{TimedOut: true, ExitCode: 137}, "x", 300 * time.Millisecond, result.Error, "timed out after 300ms", nil},
		{"interrupted", run.Outcome{Interrupted: true, ExitCode: 143}, "x", time.Minute, result.Error, "interrupted", nil},
		{"pass", run.Outcome{ExitCode: 0}, "x", time.Minute, result.Pass, "completed", ip(0)},
		{"fail 1", run.Outcome{ExitCode: 1}, "x", time.Minute, result.Fail, "exited 1", ip(1)},
		{"fail 2 is fail not skip", run.Outcome{ExitCode: 2}, "x", time.Minute, result.Fail, "exited 2", ip(2)},
		{"fail 137", run.Outcome{ExitCode: 137}, "x", time.Minute, result.Fail, "exited 137", ip(137)},
	}
	for _, c := range cases {
		st, sum, code := result.Classify(c.o, c.argv0, c.timeout)
		if st != c.status || sum != c.summary {
			t.Errorf("%s: got %s %q, want %s %q", c.name, st, sum, c.status, c.summary)
		}
		if (code == nil) != (c.code == nil) || (code != nil && *code != *c.code) {
			t.Errorf("%s: code = %v, want %v", c.name, code, c.code)
		}
	}
}

type errString string

func (e errString) Error() string { return string(e) }

func TestStatusExitCode(t *testing.T) {
	want := map[result.Status]int{result.Pass: 0, result.Fail: 1, result.Skip: 2, result.Error: 3}
	for s, c := range want {
		if s.ExitCode() != c {
			t.Errorf("%s.ExitCode() = %d, want %d", s, s.ExitCode(), c)
		}
	}
}

func TestResultJSONShape(t *testing.T) {
	b, err := json.Marshal(result.Result{ID: "x", Status: result.Pass})
	if err != nil {
		t.Fatal(err)
	}
	s := string(b)
	for _, want := range []string{
		`"findings":[]`, `"baseline":null`, `"reports":[]`, `"exit_code":null`,
		`"counts":{"error":0,"warning":0,"note":0}`, `"tree":{"head":"","diff_hash":""}`,
	} {
		if !strings.Contains(s, want) {
			t.Errorf("missing %s in %s", want, s)
		}
	}
	for _, key := range []string{"id", "script", "command", "gate", "status", "attempts", "duration_ms",
		"summary", "parsed", "guidance", "evidence", "bmax_version", "cwd", "timeout_ms", "started_at", "finished_at"} {
		if !strings.Contains(s, `"`+key+`":`) {
			t.Errorf("missing key %s", key)
		}
	}
}
