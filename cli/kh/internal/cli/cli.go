// Package cli parses arguments and runs the kh commands.
package cli

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/aether-labs-org/plugins/cli/kh/internal/evidence"
	"github.com/aether-labs-org/plugins/cli/kh/internal/redact"
	"github.com/aether-labs-org/plugins/cli/kh/internal/reduce"
	"github.com/aether-labs-org/plugins/cli/kh/internal/render"
	"github.com/aether-labs-org/plugins/cli/kh/internal/result"
	"github.com/aether-labs-org/plugins/cli/kh/internal/root"
	"github.com/aether-labs-org/plugins/cli/kh/internal/run"
	"github.com/aether-labs-org/plugins/cli/kh/internal/tree"
)

// Exit codes of kh.
const (
	ExitPass  = 0
	ExitFail  = 1
	ExitSkip  = 2
	ExitError = 3
	ExitUsage = 64
)

// Version is set from main.version.
var Version = "0.4.0-dev"

const usage = `usage:
  kh run [--timeout D] [--json] -- <command...>
  kh show <id> [--failures|--full|--json]
  kh version
`

// Run executes kh with the given arguments and returns the exit code.
func Run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprint(stderr, usage)
		return ExitUsage
	}
	switch args[0] {
	case "version":
		fmt.Fprintf(stdout, "kh %s\n", Version)
		return ExitPass
	case "run":
		return cmdRun(args[1:], stdout, stderr)
	case "show":
		return cmdShow(args[1:], stdout, stderr)
	default:
		fmt.Fprintf(stderr, "kh: unknown command %q\n%s", args[0], usage)
		return ExitUsage
	}
}

func usageErr(stderr io.Writer, format string, a ...any) int {
	fmt.Fprintf(stderr, "kh: "+format+"\n%s", append(a, usage)...)
	return ExitUsage
}

type runArgs struct {
	timeout time.Duration // 0 = default
	json    bool
	argv    []string
}

// parseRun parses what follows "kh run": flags up to "--", then the command.
func parseRun(args []string) (runArgs, error) {
	var ra runArgs
	i := 0
	for ; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "--":
			ra.argv = args[i+1:]
			if len(ra.argv) == 0 {
				return ra, errors.New("run: no command after --")
			}
			return ra, nil
		case a == "--json":
			ra.json = true
		case a == "--timeout" || strings.HasPrefix(a, "--timeout="):
			var v string
			if a == "--timeout" {
				if i+1 >= len(args) {
					return ra, errors.New("run: --timeout needs a duration")
				}
				i++
				v = args[i]
			} else {
				v = strings.TrimPrefix(a, "--timeout=")
			}
			d, err := time.ParseDuration(v)
			if err != nil || d <= 0 {
				return ra, fmt.Errorf("run: invalid --timeout %q (a positive Go duration such as 30s or 10m)", v)
			}
			ra.timeout = d
		case strings.HasPrefix(a, "-"):
			return ra, fmt.Errorf("run: unknown flag %q", a)
		default:
			return ra, fmt.Errorf("run: expected -- before the command, got %q", a)
		}
	}
	return ra, errors.New("run: missing -- and command")
}

func findRoot(stderr io.Writer) (string, int) {
	cwd, err := os.Getwd()
	if err != nil {
		fmt.Fprintf(stderr, "kh: %v\n", err)
		return "", ExitError
	}
	r, err := root.Find(cwd)
	if err != nil {
		if errors.Is(err, root.ErrNotFound) {
			fmt.Fprintln(stderr, "kh: no .agents/keel.yml here or in any parent directory")
		} else {
			fmt.Fprintf(stderr, "kh: %v\n", err)
		}
		return "", ExitError
	}
	return r, 0
}

func rel(root, p string) string {
	r, err := filepath.Rel(root, p)
	if err != nil {
		return p
	}
	return filepath.ToSlash(r)
}

func cmdRun(args []string, stdout, stderr io.Writer) int {
	ra, err := parseRun(args)
	if err != nil {
		return usageErr(stderr, "%v", err)
	}
	rootDir, code := findRoot(stderr)
	if code != 0 {
		return code
	}
	// Installed first, so that a Ctrl-C during setup is not lost: the command
	// then starts already cancelled and is killed at once.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	red := redact.New(os.Environ())
	fp := tree.Fingerprint(rootDir) // before the run: the state the command saw

	ev, err := evidence.Create(rootDir, time.Now())
	if err != nil {
		fmt.Fprintf(stderr, "kh: cannot create evidence: %v\n", err)
		return ExitError
	}
	logf, err := os.OpenFile(ev.LogPath(), os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		fmt.Fprintf(stderr, "kh: cannot create %s: %v\n", ev.LogPath(), err)
		return ExitError
	}
	w := red.Writer(logf)

	timeout := ra.timeout
	if timeout == 0 {
		timeout = run.DefaultTimeout
	}
	out := run.Run(ctx, run.Spec{Argv: ra.argv, Dir: rootDir, Timeout: timeout}, w)
	if err := w.Close(); err != nil {
		fmt.Fprintf(stderr, "kh: writing the log: %v\n", err)
	}
	logf.Close()

	status, summary, exit := result.Classify(out, ra.argv[0], timeout)
	res := result.Result{
		ID:         ev.ID,
		Command:    red.String(strings.Join(ra.argv, " ")),
		Status:     status,
		ExitCode:   exit,
		Attempts:   1,
		DurationMS: out.Finished.Sub(out.Started).Milliseconds(),
		Summary:    red.String(summary),
		Findings:   []result.Finding{},
		Evidence: result.Evidence{
			Dir:     rel(rootDir, ev.Dir),
			Log:     rel(rootDir, ev.LogPath()),
			Reports: []string{},
		},
		Tree:       fp,
		KhVersion:  Version,
		Cwd:        rootDir,
		TimeoutMS:  timeout.Milliseconds(),
		StartedAt:  out.Started.UTC(),
		FinishedAt: out.Finished.UTC(),
	}
	if err := ev.WriteMeta(res); err != nil {
		fmt.Fprintf(stderr, "kh: cannot write meta.json: %v\n", err)
		return ExitError
	}
	if err := evidence.Prune(rootDir, ev.ID, evidence.MaxRuns, evidence.MaxBytes); err != nil {
		fmt.Fprintf(stderr, "kh: warning: pruning old runs: %v\n", err)
	}

	if ra.json {
		b, err := json.MarshalIndent(res, "", "  ")
		if err != nil {
			fmt.Fprintf(stderr, "kh: %v\n", err)
			return ExitError
		}
		fmt.Fprintf(stdout, "%s\n", b)
	} else {
		reduction, _ := reduce.FromFile(ev.LogPath())
		io.WriteString(stdout, render.Run(res, reduction))
	}
	return status.ExitCode()
}

func cmdShow(args []string, stdout, stderr io.Writer) int {
	var id, mode string
	for _, a := range args {
		switch a {
		case "--failures", "--full", "--json":
			if mode != "" {
				return usageErr(stderr, "show: only one of --failures, --full, --json")
			}
			mode = a
		default:
			if strings.HasPrefix(a, "-") {
				return usageErr(stderr, "show: unknown flag %q", a)
			}
			if id != "" {
				return usageErr(stderr, "show: one run id only")
			}
			id = a
		}
	}
	if id == "" {
		return usageErr(stderr, "show: missing run id")
	}
	rootDir, code := findRoot(stderr)
	if code != 0 {
		return code
	}
	res, err := evidence.Load(rootDir, id)
	if err != nil {
		if errors.Is(err, evidence.ErrNoRun) {
			fmt.Fprintf(stderr, "kh: no run %s\n", id)
			return ExitUsage
		}
		fmt.Fprintf(stderr, "kh: %v\n", err)
		return ExitError
	}
	dir := filepath.Join(rootDir, ".agents", "run", "runs", id)
	logPath := filepath.Join(dir, "output.log")

	switch mode {
	case "--json":
		b, err := os.ReadFile(filepath.Join(dir, "meta.json"))
		if err != nil {
			fmt.Fprintf(stderr, "kh: %v\n", err)
			return ExitError
		}
		stdout.Write(b)
	case "--full":
		f, err := os.Open(logPath)
		if err != nil {
			fmt.Fprintf(stderr, "kh: %v\n", err)
			return ExitError
		}
		defer f.Close()
		if _, err := io.Copy(stdout, f); err != nil {
			fmt.Fprintf(stderr, "kh: %v\n", err)
			return ExitError
		}
	case "--failures":
		reduction, err := reduce.FromFile(logPath)
		if err != nil {
			fmt.Fprintf(stderr, "kh: %v\n", err)
			return ExitError
		}
		ctx, err := reduce.Context(logPath, reduction.Matches, 2)
		if err != nil {
			fmt.Fprintf(stderr, "kh: %v\n", err)
			return ExitError
		}
		io.WriteString(stdout, render.Failures(res, ctx))
	default:
		reduction, err := reduce.FromFile(logPath)
		if err != nil {
			fmt.Fprintf(stderr, "kh: %v\n", err)
			return ExitError
		}
		io.WriteString(stdout, render.Run(res, reduction))
	}
	return ExitPass
}
