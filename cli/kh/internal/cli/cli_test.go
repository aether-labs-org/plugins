package cli_test

import (
	"bytes"
	"encoding/json"
	"os"
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
	if out != "kh 0.4.0-dev\n" || rc != 0 {
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
		{"run", "true"},                         // missing --
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
	t.Chdir(t.TempDir())
	_, errb, rc := run("run", "--", "true")
	if rc != cli.ExitError || !strings.Contains(errb, "no .agents/keel.yml") {
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
