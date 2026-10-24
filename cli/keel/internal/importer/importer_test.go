package importer

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/aether-labs-org/plugins/cli/keel/internal/config"
)

func TestRenderIsCanonicalAndParses(t *testing.T) {
	c := &config.Config{Version: 1, Requires: "0.1.0", Sensors: []config.Sensor{
		{ID: "guard", Gate: "fast", Adapter: "guard"}, {ID: "lint", Gate: "fast", Exec: "scripts/sensors/lint.sh"},
	}}
	want := "# Managed by keel. The sensors and budgets of this repository's gates; check with `keel validate`.\n" +
		"version: 1\nrequires: 0.1.0\ngate:\n  fast:\n    ceiling_seconds: 30\n  slow:\n    ceiling_seconds: 600\n" +
		"sensors:\n  - id: guard\n    gate: fast\n    adapter: guard\n  - id: lint\n    gate: fast\n    exec: scripts/sensors/lint.sh\n"
	got := Render(c)
	if got != want {
		t.Fatalf("Render =\n%s\nwant\n%s", got, want)
	}
	if _, err := config.Parse([]byte(got)); err != nil {
		t.Fatalf("rendered keel.yaml does not parse: %v", err)
	}
}

func TestReadSums(t *testing.T) {
	p := filepath.Join(t.TempDir(), "SHA256SUMS")
	os.WriteFile(p, []byte("aaa  linux-amd64/keel\nbbb *darwin-arm64/keel\nccc  README\n"), 0o644)
	m, err := ReadSums(p)
	if err != nil || m["linux-amd64"] != "aaa" || m["darwin-arm64"] != "bbb" || len(m) != 2 {
		t.Fatalf("ReadSums = %v, %v", m, err)
	}
}
