// Package config loads and validates .agents/bmax.yml (version 1).
package config

import "time"

// Defaults and limits of bmax.yml v1.
const (
	DefaultADRDir  = "docs/adr"
	DefaultTimeout = 10 * time.Minute
	MaxRetries     = 3
	// GuardID is the reserved script id that resolves to the guard builtin.
	GuardID = "guard"
)

// RequiredGates must exist and list guard.
var RequiredGates = []string{"fast", "commit", "slow"}

// Config is a loaded bmax.yml.
type Config struct {
	Version   int
	ADRDir    string // default "docs/adr"
	ReviewDue string // "YYYY-MM-DD" or ""
	Guides    []string
	Githooks  Githooks
	Scripts   map[string]Script
	Order     []string // script ids in file order (the implicit guard is not listed)
	Gates     map[string]Gate
}

// Githooks configures the git hooks.
type Githooks struct{ Mode, PreCommit, PrePush, CommitMsg string } // Mode "native"|"external"

// Script is the one entity of bmax.yml: a command, a builtin or an exec file.
type Script struct {
	ID, Run, Builtin, Exec          string
	With                            map[string]any
	Format, Pattern, Reports, Files string
	PassFiles                       *bool
	Timeout                         time.Duration // default 10m
	Retries                         int           // 0..3
	Class                           string        // "security"|"correctness"|"heuristic"|""
	Baseline, Guidance, Decision    string
	Doc, Exemplar, Legacy           string
	Requires                        []string
	Config                          []string
	Exceptions                      []Exception
}

// Exception lets a path fail until a date; it can only shrink.
type Exception struct {
	Path  string `yaml:"path"`
	Until string `yaml:"until"`
}

// Gate is an ordered list of scripts run together.
type Gate struct {
	Name    string
	Scripts []string
	Changes string // "worktree"|"staged"|"branch"
	Ceiling time.Duration
}

// PassesFiles reports whether the changed files are appended to the command.
func (s Script) PassesFiles() bool { return s.PassFiles == nil || *s.PassFiles }

// Issue is one validation problem; Path looks like "scripts.lint.format".
type Issue struct{ Path, Msg string }

// String renders the issue as printed by bmax validate.
func (i Issue) String() string {
	if i.Path == "" {
		return "bmax.yml: " + i.Msg
	}
	return "bmax.yml: " + i.Path + ": " + i.Msg
}

// ValidationError carries every issue found.
type ValidationError struct{ Issues []Issue }

func (e *ValidationError) Error() string {
	s := ""
	for i, is := range e.Issues {
		if i > 0 {
			s += "\n"
		}
		s += is.String()
	}
	return s
}

// WithValidator checks the `with:` block of a builtin. known=false means the
// builtin does not exist; problems are strict-decode complaints.
type WithValidator func(builtin string, with map[string]any) (known bool, problems []string)
