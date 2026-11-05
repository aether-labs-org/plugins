// Package gate runs a gate: the scripts of bmax.yml in order, under a lock, and
// the verdict over them.
package gate

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/aether-labs-org/plugins/cli/bmax/internal/evidence"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/reduce"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/result"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/script"
)

// LockWait is how long a gate waits for another gate to finish.
var LockWait = 30 * time.Second

// Result is the outcome of one gate run.
type Result struct {
	ID, Name   string
	Scripts    []result.Result
	Reductions []reduce.Reduction // parallel to Scripts; filled for scripts that did not pass
	// Status is Pass unless a script failed or errored, or a security script skipped.
	Status         result.Status
	Spent, Ceiling time.Duration
	OverCeiling    bool
	StartedAt      time.Time
}

// Counts returns N scripts, P passed, F failed (failed, errored, or a skipped
// security script) and S skipped (the others).
func (r Result) Counts() (n, p, f, s int) {
	n = len(r.Scripts)
	for _, sr := range r.Scripts {
		switch {
		case sr.Status == result.Pass:
			p++
		case sr.Status == result.Skip && sr.Class != "security":
			s++
		default:
			f++
		}
	}
	return
}

// Verdict derives the status from the script results.
func Verdict(scripts []result.Result) result.Status {
	for _, sr := range scripts {
		switch {
		case sr.Status == result.Fail, sr.Status == result.Error:
			return result.Fail
		case sr.Status == result.Skip && sr.Class == "security":
			return result.Fail
		}
	}
	return result.Pass
}

// ExitCode is 0 for a passed gate and 1 for a failed one.
func (r Result) ExitCode() int {
	if r.Status == result.Pass {
		return 0
	}
	return 1
}

// Run runs gate name. The returned error is infrastructure (unknown gate, lock
// timeout, evidence); script failures are in the Result.
func Run(ctx context.Context, e script.Exec, name string) (Result, error) {
	g, ok := e.Cfg.Gates[name]
	if !ok {
		return Result{}, fmt.Errorf("unknown gate %q", name)
	}
	release, err := Acquire(e.Root, LockWait)
	if err != nil {
		return Result{}, err
	}
	defer release()

	started := time.Now()
	ev, err := evidence.Create(e.Root, started)
	if err != nil {
		return Result{}, fmt.Errorf("cannot create evidence: %w", err)
	}
	e.Gate = name
	e.Changes = scopeBase(g.Changes)
	out := Result{ID: ev.ID, Name: name, Ceiling: g.Ceiling, StartedAt: started}
	for _, sid := range g.Scripts {
		sr, err := e.Script(ctx, sid, nil)
		if err != nil {
			return out, fmt.Errorf("script %s: %w", sid, err)
		}
		out.Scripts = append(out.Scripts, sr)
		var red reduce.Reduction
		if sr.Status != result.Pass && sr.Evidence.Log != "" {
			red, _ = reduce.FromFile(filepath.Join(e.Root, sr.Evidence.Log))
		}
		out.Reductions = append(out.Reductions, red)
		if ctx.Err() != nil {
			break
		}
	}
	out.Spent = time.Since(started)
	out.Status = Verdict(out.Scripts)
	out.OverCeiling = g.Ceiling > 0 && out.Spent > g.Ceiling
	if err := writeMeta(ev, out); err != nil {
		return out, err
	}
	if err := evidence.Prune(e.Root, ev.ID, evidence.MaxRuns, evidence.MaxBytes); err != nil {
		fmt.Fprintf(os.Stderr, "bmax: warning: pruning old runs: %v\n", err)
	}
	return out, nil
}

// Meta is gate.json, stored in the gate's evidence directory.
type Meta struct {
	ID          string    `json:"id"`
	Gate        string    `json:"gate"`
	Status      string    `json:"status"`
	Scripts     []string  `json:"scripts"` // run ids, in order
	SpentMS     int64     `json:"spent_ms"`
	CeilingMS   int64     `json:"ceiling_ms"`
	OverCeiling bool      `json:"over_ceiling"`
	StartedAt   time.Time `json:"started_at"`
}

func writeMeta(ev evidence.Run, r Result) error {
	m := Meta{ID: r.ID, Gate: r.Name, Status: string(r.Status), Scripts: []string{}, SpentMS: r.Spent.Milliseconds(),
		CeilingMS: r.Ceiling.Milliseconds(), OverCeiling: r.OverCeiling, StartedAt: r.StartedAt.UTC()}
	for _, sr := range r.Scripts {
		m.Scripts = append(m.Scripts, sr.ID)
	}
	b, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(ev.Dir, "gate.json"), append(b, '\n'), 0o600)
}

// LoadMeta reads gate.json of a gate run; ok=false when id is not a gate run.
func LoadMeta(root, id string) (Meta, bool) {
	var m Meta
	b, err := os.ReadFile(filepath.Join(root, ".agents", "run", "runs", id, "gate.json"))
	if err != nil {
		return m, false
	}
	return m, json.Unmarshal(b, &m) == nil
}

// MarshalJSON is the --json output of a gate (the gate definition of bmax schema result).
func (r Result) MarshalJSON() ([]byte, error) {
	scripts := r.Scripts
	if scripts == nil {
		scripts = []result.Result{}
	}
	return json.Marshal(struct {
		ID          string          `json:"id"`
		Gate        string          `json:"gate"`
		Status      result.Status   `json:"status"`
		SpentMS     int64           `json:"spent_ms"`
		CeilingMS   int64           `json:"ceiling_ms"`
		OverCeiling bool            `json:"over_ceiling"`
		Scripts     []result.Result `json:"scripts"`
	}{r.ID, r.Name, r.Status, r.Spent.Milliseconds(), r.Ceiling.Milliseconds(), r.OverCeiling, scripts})
}
