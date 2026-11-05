// Package cli parses arguments and runs the bmax commands.
package cli

import (
	"bytes"
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

	"github.com/aether-labs-org/plugins/cli/bmax/internal/baseline"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/builtin"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/check"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/config"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/evidence"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/gate"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/hook"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/lock"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/redact"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/reduce"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/render"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/result"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/root"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/run"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/scope"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/script"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/setup"
	"github.com/aether-labs-org/plugins/cli/bmax/internal/tree"
)

// Exit codes of bmax.
const (
	ExitPass  = 0
	ExitFail  = 1
	ExitSkip  = 2
	ExitError = 3
	ExitUsage = 64
)

// Version is set from main.version.
var Version = "0.5.0-dev"

// Stdin is where the hooks read the agent's payload.
var Stdin io.Reader = os.Stdin

const usage = `usage:
  bmax run [--all] [--json] <script> [-- extra args...]
  bmax run [--timeout D] [--json] -- <command...>
  bmax show <id> [--failures|--full|--json]
  bmax gate <name> [--all] [--json]
  bmax measure <script>
  bmax guard [--json]
  bmax check [--strict] [--measure]
  bmax setup
  bmax hook pre-tool-use [--setup] | stop | commit-msg <file>
  bmax validate
  bmax schema config|result|memory
  bmax version
`

// Run executes bmax with the given arguments and returns the exit code.
func Run(args []string, stdout, stderr io.Writer) int {
	hook.Version = Version
	if len(args) == 0 {
		fmt.Fprint(stderr, usage)
		return ExitUsage
	}
	switch args[0] {
	case "version":
		fmt.Fprintf(stdout, "bmax %s\n", Version)
		return ExitPass
	case "run":
		return cmdRun(args[1:], stdout, stderr)
	case "show":
		return cmdShow(args[1:], stdout, stderr)
	case "gate":
		return cmdGate(args[1:], stdout, stderr)
	case "setup":
		return cmdSetup(args[1:], stdout, stderr)
	case "check":
		return cmdCheck(args[1:], stdout, stderr)
	case "hook":
		return cmdHook(args[1:], stdout, stderr)
	case "guard":
		return cmdGuard(args[1:], stdout, stderr)
	case "measure":
		return cmdMeasure(args[1:], stdout, stderr)
	case "validate":
		return cmdValidate(args[1:], stdout, stderr)
	case "schema":
		return cmdSchema(args[1:], stdout, stderr)
	default:
		fmt.Fprintf(stderr, "bmax: unknown command %q\n%s", args[0], usage)
		return ExitUsage
	}
}

func usageErr(stderr io.Writer, format string, a ...any) int {
	fmt.Fprintf(stderr, "bmax: "+format+"\n%s", append(a, usage)...)
	return ExitUsage
}

type runArgs struct {
	timeout time.Duration // 0 = default
	json    bool
	all     bool     // a declared script over every candidate file, as bmax gate --all
	script  string   // declared script id; "" for bmax run -- <command>
	argv    []string // the command, or the extra arguments of a script
}

// parseRun parses what follows "bmax run": flags up to "--", then the command.
func parseRun(args []string) (runArgs, error) {
	var ra runArgs
	i := 0
	for ; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "--":
			ra.argv = args[i+1:]
			if len(ra.argv) == 0 && ra.script == "" {
				return ra, errors.New("run: no command after --")
			}
			return ra, nil
		case a == "--json":
			ra.json = true
		case a == "--all":
			ra.all = true
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
		case ra.script == "":
			ra.script = a
		default:
			return ra, fmt.Errorf("run: expected -- before extra arguments, got %q", a)
		}
	}
	if ra.script != "" {
		return ra, nil // bmax run <script>
	}
	return ra, errors.New("run: missing -- and command")
}

// findRoot returns the root of a command: BMAX_ROOT when set (the wrapper of a
// repository exports it), else the repository that contains the working directory.
func findRoot(stderr io.Writer) (string, int) {
	if v := os.Getenv(root.EnvVar); v != "" {
		r, err := root.FromEnv(v)
		if err != nil {
			fmt.Fprintf(stderr, "bmax: %v\n", err)
			return "", ExitError
		}
		return r, 0
	}
	cwd, err := os.Getwd()
	if err != nil {
		fmt.Fprintf(stderr, "bmax: %v\n", err)
		return "", ExitError
	}
	r, err := root.Find(cwd)
	if err != nil {
		fmt.Fprintf(stderr, "bmax: %v\n", err)
		return "", ExitError
	}
	return r, 0
}

// checkPin compares the binary with .agents/bmax.lock. A repository with no
// lock is unpinned (the wrapper is what requires one) and passes.
func checkPin(rootDir string, stderr io.Writer) int {
	l, err := lock.Read(filepath.Join(rootDir, ".agents", "bmax.lock"))
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return 0
		}
		fmt.Fprintf(stderr, "bmax: %v\n", err)
		return ExitError
	}
	if err := lock.Check(l, Version); err != nil {
		fmt.Fprintf(stderr, "bmax: %v\n", err)
		return ExitError
	}
	return 0
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
	if ra.all && ra.script == "" {
		return usageErr(stderr, "run: --all applies to a declared script (bmax run --all <script>); bmax run -- <command> has no file scope")
	}
	if ra.script != "" {
		if ra.timeout != 0 {
			return usageErr(stderr, "run: --timeout applies to bmax run -- <command>; a declared script has its own timeout")
		}
		return cmdRunScript(rootDir, ra, stdout, stderr)
	}
	// Installed first, so that a Ctrl-C during setup is not lost: the command
	// then starts already cancelled and is killed at once.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	red := redact.New(os.Environ())
	fp := tree.Fingerprint(rootDir) // before the run: the state the command saw

	ev, err := evidence.Create(rootDir, time.Now())
	if err != nil {
		fmt.Fprintf(stderr, "bmax: cannot create evidence: %v\n", err)
		return ExitError
	}
	logf, err := os.OpenFile(ev.LogPath(), os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		fmt.Fprintf(stderr, "bmax: cannot create %s: %v\n", ev.LogPath(), err)
		return ExitError
	}
	w := red.Writer(logf)

	timeout := ra.timeout
	if timeout == 0 {
		timeout = run.DefaultTimeout
	}
	out := run.Run(ctx, run.Spec{Argv: ra.argv, Dir: rootDir, Timeout: timeout}, w)
	if err := w.Close(); err != nil {
		fmt.Fprintf(stderr, "bmax: writing the log: %v\n", err)
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
		Tree:        fp,
		BmaxVersion: Version,
		Cwd:         rootDir,
		TimeoutMS:   timeout.Milliseconds(),
		StartedAt:   out.Started.UTC(),
		FinishedAt:  out.Finished.UTC(),
	}
	if err := ev.WriteMeta(res); err != nil {
		fmt.Fprintf(stderr, "bmax: cannot write meta.json: %v\n", err)
		return ExitError
	}
	if err := evidence.Prune(rootDir, ev.ID, evidence.MaxRuns, evidence.MaxBytes); err != nil {
		fmt.Fprintf(stderr, "bmax: warning: pruning old runs: %v\n", err)
	}

	if ra.json {
		b, err := json.MarshalIndent(res, "", "  ")
		if err != nil {
			fmt.Fprintf(stderr, "bmax: %v\n", err)
			return ExitError
		}
		fmt.Fprintf(stdout, "%s\n", b)
	} else {
		reduction, _ := reduce.FromFile(ev.LogPath())
		io.WriteString(stdout, render.Run(res, reduction))
	}
	return status.ExitCode()
}

func cmdRunScript(rootDir string, ra runArgs, stdout, stderr io.Writer) int {
	cfg, code := loadConfig(rootDir, stderr)
	if code != 0 {
		return code
	}
	if _, ok := cfg.Scripts[ra.script]; !ok {
		return usageErr(stderr, "run: unknown script %q", ra.script)
	}
	if code := checkPin(rootDir, stderr); code != 0 {
		return code
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	ex := script.Exec{Root: rootDir, Cfg: cfg, Changes: scope.Worktree, All: ra.all, BmaxVersion: Version}
	res, err := ex.Script(ctx, ra.script, ra.argv)
	if err != nil {
		fmt.Fprintf(stderr, "bmax: %v\n", err)
		return ExitError
	}
	return printResult(rootDir, res, ra.json, stdout, stderr)
}

// printResult writes a result as JSON or as the compact text and returns its exit code.
func printResult(rootDir string, res result.Result, asJSON bool, stdout, stderr io.Writer) int {
	if asJSON {
		b, err := json.MarshalIndent(res, "", "  ")
		if err != nil {
			fmt.Fprintf(stderr, "bmax: %v\n", err)
			return ExitError
		}
		fmt.Fprintf(stdout, "%s\n", b)
	} else {
		reduction, _ := reduce.FromFile(filepath.Join(rootDir, res.Evidence.Log))
		io.WriteString(stdout, render.Run(res, reduction))
	}
	return res.Status.ExitCode()
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
	if m, ok := gate.LoadMeta(rootDir, id); ok {
		return showGate(rootDir, m, stdout)
	}
	res, err := evidence.Load(rootDir, id)
	if err != nil {
		if errors.Is(err, evidence.ErrNoRun) {
			fmt.Fprintf(stderr, "bmax: no run %s\n", id)
			return ExitUsage
		}
		fmt.Fprintf(stderr, "bmax: %v\n", err)
		return ExitError
	}
	dir := filepath.Join(rootDir, ".agents", "run", "runs", id)
	logPath := filepath.Join(dir, "output.log")

	switch mode {
	case "--json":
		b, err := os.ReadFile(filepath.Join(dir, "meta.json"))
		if err != nil {
			fmt.Fprintf(stderr, "bmax: %v\n", err)
			return ExitError
		}
		stdout.Write(b)
	case "--full":
		f, err := os.Open(logPath)
		if err != nil {
			fmt.Fprintf(stderr, "bmax: %v\n", err)
			return ExitError
		}
		defer f.Close()
		if _, err := io.Copy(stdout, f); err != nil {
			fmt.Fprintf(stderr, "bmax: %v\n", err)
			return ExitError
		}
	case "--failures":
		reduction, err := reduce.FromFile(logPath)
		if err != nil {
			fmt.Fprintf(stderr, "bmax: %v\n", err)
			return ExitError
		}
		ctx, err := reduce.Context(logPath, reduction.Matches, 2)
		if err != nil {
			fmt.Fprintf(stderr, "bmax: %v\n", err)
			return ExitError
		}
		io.WriteString(stdout, render.Failures(res, ctx))
	default:
		reduction, err := reduce.FromFile(logPath)
		if err != nil {
			fmt.Fprintf(stderr, "bmax: %v\n", err)
			return ExitError
		}
		io.WriteString(stdout, render.Run(res, reduction))
	}
	return ExitPass
}

// withValidator checks the with: blocks of builtins.
var withValidator config.WithValidator = builtin.Default().Validator()

// loadConfig loads and validates bmax.yml at the root. Problems are printed
// one per line and the exit code is returned (0 when the config is valid).
func loadConfig(rootDir string, stderr io.Writer) (*config.Config, int) {
	c, err := config.LoadValid(rootDir, withValidator)
	if err == nil {
		return c, 0
	}
	var ve *config.ValidationError
	if errors.As(err, &ve) {
		for _, is := range ve.Issues {
			fmt.Fprintln(stderr, is.String())
		}
	} else {
		fmt.Fprintf(stderr, "bmax: %v\n", err)
	}
	return nil, ExitError
}

func cmdValidate(args []string, stdout, stderr io.Writer) int {
	if len(args) > 0 {
		return usageErr(stderr, "validate: takes no arguments")
	}
	rootDir, code := findRoot(stderr)
	if code != 0 {
		return code
	}
	_, code = loadConfig(rootDir, stderr)
	return code
}

func cmdSchema(args []string, stdout, stderr io.Writer) int {
	if len(args) != 1 {
		return usageErr(stderr, "schema: expected one of config, result, memory")
	}
	b, ok := config.Schema(args[0])
	if !ok {
		return usageErr(stderr, "schema: unknown schema %q (config, result, memory)", args[0])
	}
	if args[0] == "config" {
		// the with: block of every builtin, generated from the same definitions Decode uses
		full, err := builtin.Default().ConfigSchema(b)
		if err != nil {
			fmt.Fprintf(stderr, "bmax: %v\n", err)
			return ExitError
		}
		b = append(full, '\n')
	}
	stdout.Write(b)
	return ExitPass
}

func cmdGate(args []string, stdout, stderr io.Writer) int {
	var name string
	var all, asJSON bool
	for _, a := range args {
		switch {
		case a == "--all":
			all = true
		case a == "--json":
			asJSON = true
		case strings.HasPrefix(a, "-"):
			return usageErr(stderr, "gate: unknown flag %q", a)
		case name == "":
			name = a
		default:
			return usageErr(stderr, "gate: one gate name only")
		}
	}
	if name == "" {
		return usageErr(stderr, "gate: missing gate name")
	}
	rootDir, code := findRoot(stderr)
	if code != 0 {
		return code
	}
	cfg, code := loadConfig(rootDir, stderr)
	if code != 0 {
		return code
	}
	if _, ok := cfg.Gates[name]; !ok {
		return usageErr(stderr, "gate: unknown gate %q", name)
	}
	if code := checkPin(rootDir, stderr); code != 0 {
		return code
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	ex := script.Exec{Root: rootDir, Cfg: cfg, All: all, BmaxVersion: Version}
	r, err := gate.Run(ctx, ex, name)
	if err != nil {
		fmt.Fprintf(stderr, "bmax: %v\n", err)
		return ExitError
	}
	if asJSON {
		b, err := json.MarshalIndent(r, "", "  ")
		if err != nil {
			fmt.Fprintf(stderr, "bmax: %v\n", err)
			return ExitError
		}
		fmt.Fprintf(stdout, "%s\n", b)
		return r.ExitCode()
	}
	io.WriteString(stdout, render.Gate(r))
	return r.ExitCode()
}

func showGate(rootDir string, m gate.Meta, stdout io.Writer) int {
	fmt.Fprintf(stdout, "gate: %s - %s | run %s\n", m.Gate, strings.ToUpper(m.Status), m.ID)
	for _, sid := range m.Scripts {
		res, err := evidence.Load(rootDir, sid)
		if err != nil {
			fmt.Fprintf(stdout, "  %s  (evidence pruned)\n", sid)
			continue
		}
		fmt.Fprintf(stdout, "  %s  %s  %s  [run %s]\n", res.Script, strings.ToUpper(string(res.Status)), res.Summary, res.ID)
	}
	return ExitPass
}

func cmdMeasure(args []string, stdout, stderr io.Writer) int {
	if len(args) != 1 || strings.HasPrefix(args[0], "-") {
		return usageErr(stderr, "measure: expected one script id")
	}
	rootDir, code := findRoot(stderr)
	if code != 0 {
		return code
	}
	cfg, code := loadConfig(rootDir, stderr)
	if code != 0 {
		return code
	}
	if _, ok := cfg.Scripts[args[0]]; !ok {
		return usageErr(stderr, "measure: unknown script %q", args[0])
	}
	if code := checkPin(rootDir, stderr); code != 0 {
		return code
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	ex := script.Exec{Root: rootDir, Cfg: cfg, Changes: scope.Worktree, BmaxVersion: Version}
	counts, err := ex.Measure(ctx, args[0])
	if err != nil {
		fmt.Fprintf(stderr, "bmax: measure: %v\n", err)
		return ExitError
	}
	io.WriteString(stdout, baseline.Format(counts, time.Now()))
	return ExitPass
}

// cmdGuard runs the guard script of the repository (the guard builtin).
func cmdGuard(args []string, stdout, stderr io.Writer) int {
	asJSON := false
	for _, a := range args {
		if a != "--json" {
			return usageErr(stderr, "guard: unexpected argument %q", a)
		}
		asJSON = true
	}
	rootDir, code := findRoot(stderr)
	if code != 0 {
		return code
	}
	cfg, code := loadConfig(rootDir, stderr)
	if code != 0 {
		return code
	}
	if code := checkPin(rootDir, stderr); code != 0 {
		return code
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	ex := script.Exec{Root: rootDir, Cfg: cfg, Changes: scope.Worktree, BmaxVersion: Version}
	res, err := ex.Script(ctx, config.GuardID, nil)
	if err != nil {
		fmt.Fprintf(stderr, "bmax: %v\n", err)
		return ExitError
	}
	return printResult(rootDir, res, asJSON, stdout, stderr)
}

// cmdHook runs the agent and git hooks. The agent hooks always exit 0 and, when
// bmax cannot do its job (no repository, invalid config, pin mismatch), answer
// through hook.FailSafe so that protection does not silently disappear.
func cmdHook(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		return usageErr(stderr, "hook: expected pre-tool-use, stop or commit-msg")
	}
	switch args[0] {
	case "pre-tool-use":
		setup := false
		for _, a := range args[1:] {
			if a != "--setup" {
				return usageErr(stderr, "hook pre-tool-use: unexpected argument %q", a)
			}
			setup = true
		}
		return hookPreToolUse(setup, stdout)
	case "stop":
		if len(args) != 1 {
			return usageErr(stderr, "hook stop: takes no arguments")
		}
		return hookStop(stdout, stderr)
	case "commit-msg":
		if len(args) != 2 {
			return usageErr(stderr, "hook commit-msg: expected the message file")
		}
		return hookCommitMsg(args[1], stderr)
	}
	return usageErr(stderr, "hook: unknown hook %q", args[0])
}

func readStdin() []byte {
	b, _ := io.ReadAll(io.LimitReader(Stdin, 8<<20))
	return b
}

// hookProject finds the project root of an agent hook: BMAX_ROOT when set (the
// wrapper of a repository exports it), else the repository that contains the
// working directory of the payload. "" means the session has no project: in setup
// mode when the working directory is in no repository, in project mode when its
// repository has no .agents/bmax.yml. Each write target is then judged by the
// repository that contains it (hook.PreToolUse).
func hookProject(cwd string, setup bool) (string, error) {
	if v := os.Getenv(root.EnvVar); v != "" {
		if setup {
			return root.Pinned(v)
		}
		return root.FromEnv(v)
	}
	if cwd == "" {
		cwd, _ = os.Getwd()
	}
	if setup {
		r, err := root.Toplevel(cwd)
		if errors.Is(err, root.ErrNotGit) {
			return "", nil
		}
		return r, err
	}
	r, err := root.Find(cwd)
	if errors.Is(err, root.ErrNotFound) {
		return "", nil
	}
	return r, err
}

func hookPreToolUse(setup bool, stdout io.Writer) int {
	data := readStdin()
	fail := func(reason string) int {
		hook.FailSafe("pre-tool-use", bytes.NewReader(data), stdout, reason)
		return 0
	}
	p, err := hook.Parse(bytes.NewReader(data))
	if err != nil {
		return fail("the hook payload is not JSON: " + err.Error())
	}
	rootDir, err := hookProject(p.Cwd, setup)
	if err != nil {
		if errors.Is(err, root.ErrNotGit) {
			return fail("the working directory is not in a git repository")
		}
		return fail(err.Error())
	}
	var cfg *config.Config
	if rootDir != "" {
		if _, statErr := os.Stat(filepath.Join(rootDir, ".agents", "bmax.yml")); statErr == nil {
			cfg, err = config.LoadValid(rootDir, withValidator)
			if err != nil {
				if setup {
					cfg = nil // the setup session is how a broken config gets fixed
				} else {
					return fail("cannot use .agents/bmax.yml (" + firstLine(err.Error()) + "); run sh .agents/bin/bmax validate")
				}
			}
		} else if !setup {
			return fail("no .agents/bmax.yml")
		}
		if !setup {
			if code := checkPin(rootDir, io.Discard); code != 0 {
				var buf strings.Builder
				checkPin(rootDir, &buf)
				return fail(strings.TrimPrefix(firstLine(buf.String()), "bmax: "))
			}
		}
	}
	hook.WritePreToolUse(stdout, hook.PreToolUse(rootDir, cfg, p, setup))
	return 0
}

func firstLine(s string) string {
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return s[:i]
	}
	return s
}

func hookStop(stdout, stderr io.Writer) int {
	data := readStdin()
	fail := func(reason string) int {
		hook.FailSafe("stop", bytes.NewReader(data), stdout, reason)
		return 0
	}
	p, err := hook.Parse(bytes.NewReader(data))
	if err != nil {
		return fail("the hook payload is not JSON")
	}
	rootDir, err := hookProject(p.Cwd, false)
	if err == nil && rootDir == "" {
		err = root.ErrNotFound
	}
	if err != nil {
		if errors.Is(err, root.ErrNotGit) {
			return fail("the working directory is not in a git repository")
		}
		return fail(err.Error())
	}
	var buf strings.Builder
	if checkPin(rootDir, &buf) != 0 {
		return fail(strings.TrimPrefix(firstLine(buf.String()), "bmax: "))
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	return hook.Stop(ctx, rootDir, p, stdout, stderr)
}

func hookCommitMsg(file string, stderr io.Writer) int {
	rootDir, code := findRoot(stderr)
	if code != 0 {
		return 1
	}
	if code := checkPin(rootDir, stderr); code != 0 {
		return 1
	}
	return hook.CommitMsg(context.Background(), rootDir, file, stderr)
}

// cmdCheck prints the warnings of bmax check. It is exempt from the pin check
// (it reports pin-mismatch). An invalid bmax.yml exits 3 with the bmax validate lines.
func cmdCheck(args []string, stdout, stderr io.Writer) int {
	strict, measure := false, false
	for _, a := range args {
		switch a {
		case "--strict":
			strict = true
		case "--measure":
			measure = true
		default:
			return usageErr(stderr, "check: unexpected argument %q", a)
		}
	}
	rootDir, code := findRoot(stderr)
	if code != 0 {
		return code
	}
	cfg, code := loadConfig(rootDir, stderr)
	if code != 0 {
		return code
	}
	var opts check.Options
	if measure {
		ex := script.Exec{Root: rootDir, Cfg: cfg, BmaxVersion: Version}
		opts.Measure = func(id string) (map[string]int, error) {
			ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
			defer stop()
			return ex.Measure(ctx, id)
		}
	}
	ws := check.RunWith(rootDir, cfg, Version, opts)
	for _, w := range ws {
		fmt.Fprintf(stdout, "warn %s: %s\n", w.ID, w.Message)
	}
	if strict && len(ws) > 0 {
		return ExitFail
	}
	return ExitPass
}

// cmdSetup is the per-clone step: activate the native git hooks, then run bmax
// check and print its warnings. It exits 0 whatever the warnings say.
func cmdSetup(args []string, stdout, stderr io.Writer) int {
	if len(args) > 0 {
		return usageErr(stderr, "setup: takes no arguments")
	}
	rootDir, code := findRoot(stderr)
	if code != 0 {
		return code
	}
	cfg, code := loadConfig(rootDir, stderr)
	if code != 0 {
		return code
	}
	if code := checkPin(rootDir, stderr); code != 0 {
		return code
	}
	if err := setup.Run(rootDir, cfg, stdout); err != nil {
		fmt.Fprintf(stderr, "bmax: setup: %v\n", err)
		return ExitError
	}
	for _, w := range check.Run(rootDir, cfg, Version) {
		fmt.Fprintf(stdout, "warn %s: %s\n", w.ID, w.Message)
	}
	return ExitPass
}
