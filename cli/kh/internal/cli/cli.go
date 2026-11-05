// Package cli parses arguments and runs the kh commands.
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

	"github.com/aether-labs-org/plugins/cli/kh/internal/baseline"
	"github.com/aether-labs-org/plugins/cli/kh/internal/builtin"
	"github.com/aether-labs-org/plugins/cli/kh/internal/check"
	"github.com/aether-labs-org/plugins/cli/kh/internal/config"
	"github.com/aether-labs-org/plugins/cli/kh/internal/evidence"
	"github.com/aether-labs-org/plugins/cli/kh/internal/gate"
	"github.com/aether-labs-org/plugins/cli/kh/internal/hook"
	"github.com/aether-labs-org/plugins/cli/kh/internal/lock"
	"github.com/aether-labs-org/plugins/cli/kh/internal/redact"
	"github.com/aether-labs-org/plugins/cli/kh/internal/reduce"
	"github.com/aether-labs-org/plugins/cli/kh/internal/render"
	"github.com/aether-labs-org/plugins/cli/kh/internal/result"
	"github.com/aether-labs-org/plugins/cli/kh/internal/root"
	"github.com/aether-labs-org/plugins/cli/kh/internal/run"
	"github.com/aether-labs-org/plugins/cli/kh/internal/scope"
	"github.com/aether-labs-org/plugins/cli/kh/internal/script"
	"github.com/aether-labs-org/plugins/cli/kh/internal/setup"
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
var Version = "0.5.0-dev"

// Stdin is where the hooks read the agent's payload.
var Stdin io.Reader = os.Stdin

const usage = `usage:
  kh run [--json] <script> [-- extra args...]
  kh run [--timeout D] [--json] -- <command...>
  kh show <id> [--failures|--full|--json]
  kh gate <name> [--all] [--json]
  kh measure <script>
  kh guard [--json]
  kh check [--strict] [--measure]
  kh setup
  kh hook pre-tool-use [--setup] | stop | commit-msg <file>
  kh validate
  kh schema keel|result|memory
  kh version
`

// Run executes kh with the given arguments and returns the exit code.
func Run(args []string, stdout, stderr io.Writer) int {
	hook.Version = Version
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
	script  string   // declared script id; "" for kh run -- <command>
	argv    []string // the command, or the extra arguments of a script
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
			if len(ra.argv) == 0 && ra.script == "" {
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
		case ra.script == "":
			ra.script = a
		default:
			return ra, fmt.Errorf("run: expected -- before extra arguments, got %q", a)
		}
	}
	if ra.script != "" {
		return ra, nil // kh run <script>
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
		fmt.Fprintf(stderr, "kh: %v\n", err)
		return "", ExitError
	}
	return r, 0
}

// checkPin compares the binary with .agents/keel.lock. A repository with no
// lock is unpinned (the wrapper is what requires one) and passes.
func checkPin(rootDir string, stderr io.Writer) int {
	l, err := lock.Read(filepath.Join(rootDir, ".agents", "keel.lock"))
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return 0
		}
		fmt.Fprintf(stderr, "kh: %v\n", err)
		return ExitError
	}
	if err := lock.Check(l, Version); err != nil {
		fmt.Fprintf(stderr, "kh: %v\n", err)
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
	if ra.script != "" {
		if ra.timeout != 0 {
			return usageErr(stderr, "run: --timeout applies to kh run -- <command>; a declared script has its own timeout")
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
	ex := script.Exec{Root: rootDir, Cfg: cfg, Changes: scope.Worktree, KhVersion: Version}
	res, err := ex.Script(ctx, ra.script, ra.argv)
	if err != nil {
		fmt.Fprintf(stderr, "kh: %v\n", err)
		return ExitError
	}
	return printResult(rootDir, res, ra.json, stdout, stderr)
}

// printResult writes a result as JSON or as the compact text and returns its exit code.
func printResult(rootDir string, res result.Result, asJSON bool, stdout, stderr io.Writer) int {
	if asJSON {
		b, err := json.MarshalIndent(res, "", "  ")
		if err != nil {
			fmt.Fprintf(stderr, "kh: %v\n", err)
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

// withValidator checks the with: blocks of builtins.
var withValidator config.WithValidator = builtin.Default().Validator()

// loadConfig loads and validates keel.yml at the root. Problems are printed
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
		fmt.Fprintf(stderr, "kh: %v\n", err)
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
		return usageErr(stderr, "schema: expected one of keel, result, memory")
	}
	b, ok := config.Schema(args[0])
	if !ok {
		return usageErr(stderr, "schema: unknown schema %q (keel, result, memory)", args[0])
	}
	if args[0] == "keel" {
		// the with: block of every builtin, generated from the same definitions Decode uses
		full, err := builtin.Default().KeelSchema(b)
		if err != nil {
			fmt.Fprintf(stderr, "kh: %v\n", err)
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
	ex := script.Exec{Root: rootDir, Cfg: cfg, All: all, KhVersion: Version}
	r, err := gate.Run(ctx, ex, name)
	if err != nil {
		fmt.Fprintf(stderr, "kh: %v\n", err)
		return ExitError
	}
	if asJSON {
		b, err := json.MarshalIndent(r, "", "  ")
		if err != nil {
			fmt.Fprintf(stderr, "kh: %v\n", err)
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
	ex := script.Exec{Root: rootDir, Cfg: cfg, Changes: scope.Worktree, KhVersion: Version}
	counts, err := ex.Measure(ctx, args[0])
	if err != nil {
		fmt.Fprintf(stderr, "kh: measure: %v\n", err)
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
	ex := script.Exec{Root: rootDir, Cfg: cfg, Changes: scope.Worktree, KhVersion: Version}
	res, err := ex.Script(ctx, config.GuardID, nil)
	if err != nil {
		fmt.Fprintf(stderr, "kh: %v\n", err)
		return ExitError
	}
	return printResult(rootDir, res, asJSON, stdout, stderr)
}

// cmdHook runs the agent and git hooks. The agent hooks always exit 0 and, when
// kh cannot do its job (no repository, invalid config, pin mismatch), answer
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

// hookRoot finds the repository root from the payload's working directory.
func hookRoot(cwd string, setup bool) (string, error) {
	if cwd == "" {
		cwd, _ = os.Getwd()
	}
	if setup {
		return root.Toplevel(cwd)
	}
	return root.Find(cwd)
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
	rootDir, err := hookRoot(p.Cwd, setup)
	if err != nil {
		return fail(err.Error() + "; run sh .agents/bin/kh setup")
	}
	var cfg *config.Config
	if _, statErr := os.Stat(filepath.Join(rootDir, ".agents", "keel.yml")); statErr == nil {
		cfg, err = config.LoadValid(rootDir, withValidator)
		if err != nil {
			if setup {
				cfg = nil // the setup session is how a broken config gets fixed
			} else {
				return fail("cannot use .agents/keel.yml (" + firstLine(err.Error()) + "); run sh .agents/bin/kh validate")
			}
		}
	} else if !setup {
		return fail("no .agents/keel.yml")
	}
	if !setup {
		if code := checkPin(rootDir, io.Discard); code != 0 {
			var buf strings.Builder
			checkPin(rootDir, &buf)
			return fail(strings.TrimPrefix(firstLine(buf.String()), "kh: "))
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
	rootDir, err := hookRoot(p.Cwd, false)
	if err != nil {
		return fail(err.Error())
	}
	var buf strings.Builder
	if checkPin(rootDir, &buf) != 0 {
		return fail(strings.TrimPrefix(firstLine(buf.String()), "kh: "))
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

// cmdCheck prints the warnings of kh check. It is exempt from the pin check
// (it reports pin-mismatch). An invalid keel.yml exits 3 with the kh validate lines.
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
		ex := script.Exec{Root: rootDir, Cfg: cfg, KhVersion: Version}
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

// cmdSetup is the per-clone step: activate the native git hooks, then run kh
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
		fmt.Fprintf(stderr, "kh: setup: %v\n", err)
		return ExitError
	}
	for _, w := range check.Run(rootDir, cfg, Version) {
		fmt.Fprintf(stdout, "warn %s: %s\n", w.ID, w.Message)
	}
	return ExitPass
}
