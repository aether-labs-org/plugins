package hook

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/aether-labs-org/plugins/cli/kh/internal/builtin"
	"github.com/aether-labs-org/plugins/cli/kh/internal/config"
	"github.com/aether-labs-org/plugins/cli/kh/internal/gate"
	"github.com/aether-labs-org/plugins/cli/kh/internal/render"
	"github.com/aether-labs-org/plugins/cli/kh/internal/result"
	"github.com/aether-labs-org/plugins/cli/kh/internal/script"
	"github.com/aether-labs-org/plugins/cli/kh/internal/tree"
)

// stopState is .agents/run/stop-state.json.
type stopState struct {
	Green   string `json:"green"`   // tree fingerprint of the last green run
	Relayed string `json:"relayed"` // failure fingerprint already handed to the agent
}

func statePath(root string) string { return filepath.Join(root, ".agents", "run", "stop-state.json") }

func loadState(root string) stopState {
	var st stopState
	if b, err := os.ReadFile(statePath(root)); err == nil {
		_ = json.Unmarshal(b, &st)
	}
	return st
}

func saveState(root string, st stopState) {
	b, _ := json.Marshal(st)
	_ = os.MkdirAll(filepath.Dir(statePath(root)), 0o700)
	tmp := statePath(root) + ".tmp"
	if os.WriteFile(tmp, append(b, '\n'), 0o600) == nil {
		_ = os.Rename(tmp, statePath(root))
	}
}

func treeKey(t result.Tree) string { return t.Head + ":" + t.DiffHash }

// failureFingerprint hashes the failing results: script id, status and
// file:line:rule of each finding, sorted. The tree is not part of it, so the
// same failure is recognised after unrelated edits.
func failureFingerprint(r gate.Result) string {
	var parts []string
	for _, sr := range r.Scripts {
		failing := sr.Status == result.Fail || sr.Status == result.Error || (sr.Status == result.Skip && sr.Class == "security")
		if !failing {
			continue
		}
		if len(sr.Findings) == 0 {
			parts = append(parts, fmt.Sprintf("%s|%s||", sr.Script, sr.Status))
		}
		for _, f := range sr.Findings {
			parts = append(parts, fmt.Sprintf("%s|%s|%s:%d:%s", sr.Script, sr.Status, f.File, f.Line, f.Rule))
		}
	}
	sort.Strings(parts)
	sum := sha256.Sum256([]byte(strings.Join(parts, "\n")))
	return hex.EncodeToString(sum[:])
}

// Stop runs the fast gate at the end of an agent turn when the tree changed
// since the last green result. A failure is handed to the agent once ({"decision":
// "block"}); the same failure (same fingerprint) is not relayed again, on this turn
// or a later one: the agent may stop and the human is told. An invalid config or a gate that cannot run never blocks. The return
// value is the exit code of the hook (always 0).
func Stop(ctx context.Context, root string, p Payload, w, errw io.Writer) int {
	cfg, err := config.LoadValid(root, builtin.Default().Validator())
	if err != nil {
		writeSystemMessage(w, "kh: the fast gate did not run: "+firstLine(err.Error()))
		return 0
	}
	if _, ok := cfg.Gates["fast"]; !ok {
		writeSystemMessage(w, "kh: the fast gate did not run: no gate named fast in .agents/keel.yml")
		return 0
	}
	st := loadState(root)
	fp := treeKey(tree.Fingerprint(root))
	if st.Green != "" && st.Green == fp {
		return 0
	}
	ex := script.Exec{Root: root, Cfg: cfg, KhVersion: Version}
	r, err := gate.Run(ctx, ex, "fast")
	if err != nil {
		writeSystemMessage(w, "kh: the fast gate did not run: "+firstLine(err.Error()))
		return 0
	}
	if r.Status == result.Pass {
		// green: remember the tree, forget the relayed failure (a recurrence after a fix is a new occurrence)
		saveState(root, stopState{Green: fp})
		return 0
	}
	ff := failureFingerprint(r)
	// at most one forced continuation per DISTINCT failure: the same failure is never relayed twice,
	// whatever stop_hook_active says (it is false at the start of every new user turn)
	if ff == st.Relayed {
		msg := render.GateVerdict(r) + " - the agent stopped with this failure"
		writeSystemMessage(w, msg)
		fmt.Fprintln(errw, msg)
		saveState(root, stopState{Relayed: ff}) // not green, the failure stays remembered
		return 0
	}
	writeStopBlock(w, render.Gate(r))
	saveState(root, stopState{Relayed: ff})
	return 0
}

// Version is the kh version, set by the cli package.
var Version = "dev"

func firstLine(s string) string {
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return s[:i]
	}
	return s
}
