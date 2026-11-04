// Package result defines the Result type: it is both meta.json and the --json
// output of kh, one schema.
package result

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/aether-labs-org/plugins/cli/kh/internal/run"
)

// Status is the verdict of one execution.
type Status string

const (
	Pass  Status = "pass"
	Fail  Status = "fail"
	Skip  Status = "skip"
	Error Status = "error"
)

// ExitCode is the exit code of kh run for the status.
func (s Status) ExitCode() int {
	switch s {
	case Pass:
		return 0
	case Fail:
		return 1
	case Skip:
		return 2
	default:
		return 3
	}
}

// Counts holds the number of findings per severity.
type Counts struct {
	Error   int `json:"error"`
	Warning int `json:"warning"`
	Note    int `json:"note"`
}

// Finding is one problem reported by a tool (filled by parsers in later milestones).
type Finding struct {
	File     string `json:"file"`
	Line     int    `json:"line"`
	Col      int    `json:"col"`
	Rule     string `json:"rule"`
	Severity string `json:"severity"`
	Message  string `json:"message"`
}

// Baseline is the comparison with a baseline file (filled in later milestones).
type Baseline struct {
	File string   `json:"file"`
	Over []string `json:"over"`
}

// Evidence locates the stored evidence; paths are relative to the root.
type Evidence struct {
	Dir     string   `json:"dir"`
	Log     string   `json:"log"`
	Reports []string `json:"reports"`
}

// Tree fingerprints the work tree the command saw.
type Tree struct {
	Head     string `json:"head"`
	DiffHash string `json:"diff_hash"`
}

// Result is the outcome of one execution.
type Result struct {
	ID         string    `json:"id"`
	Script     string    `json:"script"`
	Command    string    `json:"command"`
	Gate       string    `json:"gate"`
	Status     Status    `json:"status"`
	ExitCode   *int      `json:"exit_code"`
	Attempts   int       `json:"attempts"`
	DurationMS int64     `json:"duration_ms"`
	Summary    string    `json:"summary"`
	Counts     Counts    `json:"counts"`
	Findings   []Finding `json:"findings"`
	Parsed     bool      `json:"parsed"`
	Baseline   *Baseline `json:"baseline"`
	Guidance   string    `json:"guidance"`
	Evidence   Evidence  `json:"evidence"`
	Tree       Tree      `json:"tree"`
	KhVersion  string    `json:"kh_version"`
	Cwd        string    `json:"cwd"`
	TimeoutMS  int64     `json:"timeout_ms"`
	StartedAt  time.Time `json:"started_at"`
	FinishedAt time.Time `json:"finished_at"`
}

// MarshalJSON guarantees that empty lists are [] and never null.
func (r Result) MarshalJSON() ([]byte, error) {
	type plain Result // no methods: avoids recursion
	p := plain(r)
	if p.Findings == nil {
		p.Findings = []Finding{}
	}
	if p.Evidence.Reports == nil {
		p.Evidence.Reports = []string{}
	}
	if p.Baseline != nil && p.Baseline.Over == nil {
		b := *p.Baseline
		b.Over = []string{}
		p.Baseline = &b
	}
	return json.Marshal(p)
}

// Classify derives the status, the summary and the exit code to record from
// what happened to the process. It never looks at the output.
func Classify(o run.Outcome, argv0 string, timeout time.Duration) (Status, string, *int) {
	switch {
	case o.NotFound:
		return Skip, argv0 + " not found - run: make bootstrap", nil
	case o.StartErr != nil:
		return Error, "cannot start: " + o.StartErr.Error(), nil
	case o.TimedOut:
		return Error, "timed out after " + timeout.String(), nil
	case o.Interrupted:
		return Error, "interrupted", nil
	}
	code := o.ExitCode
	if code == 0 {
		return Pass, "completed", &code
	}
	return Fail, fmt.Sprintf("exited %d", code), &code
}
