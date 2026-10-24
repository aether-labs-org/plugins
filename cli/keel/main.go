// keel runs a repository's gates from .agents/keel.yaml, keeping keel's sensor contract byte for byte.
package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/aether-labs-org/plugins/cli/keel/internal/config"
	"github.com/aether-labs-org/plugins/cli/keel/internal/gate"
	"github.com/aether-labs-org/plugins/cli/keel/internal/guard"
	"github.com/aether-labs-org/plugins/cli/keel/internal/importer"
)

// version is the keel release; `make dist` sets it with -ldflags "-X main.version=...".
var version = "0.1.0"

const (
	exitConfig = 3  // keel.yaml, keel.lock or the pin is wrong: never a pass
	exitUsage  = 64 // bad command line, as gate.sh
)

const usage = `usage: keel <command>
  keel gate [fast|slow]        run a gate and print its report (exit 0 pass, 1 fail)
  keel gate --sensor <id>      run one sensor with SCOPE as given; print its contract output
  keel measure <id>            the same with KEEL_MEASURE=1 (baseline rows)
  keel guard                   run the guard sensor
  keel validate                check .agents/keel.yaml, .agents/keel.lock and the pin
  keel import [--force] [--sums FILE]   write keel.yaml (and keel.lock) from a bash-engine install
  keel version
`

func init() { gate.Adapters["guard"] = guard.Run }

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }

// findRoot walks up from the working directory to the directory holding .agents/keel.yaml.
func findRoot() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, config.File)); err == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("no %s here or in any parent directory - run keel import or /keel-harness:build", config.File)
		}
		dir = parent
	}
}

// load finds the repository, validates keel.yaml and checks the pin; every failure is exitConfig.
func load(stderr io.Writer) (string, *config.Config, bool) {
	root, err := findRoot()
	if err == nil {
		var c *config.Config
		if c, err = config.Load(root); err == nil {
			if err = config.CheckPin(root, c, version); err == nil {
				return root, c, true
			}
		}
	}
	fmt.Fprintf(stderr, "keel: %v\n", err)
	return "", nil, false
}

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprint(stderr, usage)
		return exitUsage
	}
	switch cmd, rest := args[0], args[1:]; cmd {
	case "version", "--version":
		fmt.Fprintf(stdout, "keel %s\n", version)
		return 0
	case "validate":
		root, c, ok := load(stderr)
		if !ok {
			return exitConfig
		}
		_ = root
		fmt.Fprintf(stdout, "keel: %s is valid (%d sensors, keel %s pinned)\n", config.File, len(c.Sensors), c.Requires)
		return 0
	case "gate":
		if len(rest) == 2 && rest[0] == "--sensor" {
			return sensor(rest[1], os.Environ(), stdout, stderr)
		}
		mode := "fast"
		if len(rest) == 1 {
			mode = rest[0]
		}
		if len(rest) > 1 || (mode != "fast" && mode != "slow") {
			fmt.Fprintln(stderr, "usage: keel gate [fast|slow] | keel gate --sensor <id>")
			return exitUsage
		}
		root, c, ok := load(stderr)
		if !ok {
			return exitConfig
		}
		return gate.Run(root, mode, c, stdout, gate.IsTTY(os.Stdout))
	case "measure":
		if len(rest) != 1 {
			fmt.Fprintln(stderr, "usage: keel measure <id>")
			return exitUsage
		}
		return sensor(rest[0], append(os.Environ(), "KEEL_MEASURE=1"), stdout, stderr)
	case "guard":
		root, _, ok := load(stderr)
		if !ok {
			return exitConfig
		}
		out, rc := guard.Run(root)
		io.WriteString(stdout, out)
		return rc
	case "import":
		return doImport(rest, stdout, stderr)
	default:
		fmt.Fprint(stderr, usage)
		return exitUsage
	}
}

// sensor runs one listed sensor with the caller's environment (SCOPE included, not recomputed).
func sensor(id string, env []string, stdout, stderr io.Writer) int {
	root, c, ok := load(stderr)
	if !ok {
		return exitConfig
	}
	s, found := c.Find(id)
	if !found {
		fmt.Fprintf(stderr, "keel: no sensor %q in %s\n", id, config.File)
		return exitUsage
	}
	out, rc := gate.RunSensor(root, s, env)
	io.WriteString(stdout, out)
	return rc
}

func doImport(args []string, stdout, stderr io.Writer) int {
	force, sums := false, ""
	for i := 0; i < len(args); i++ {
		switch {
		case args[i] == "--force":
			force = true
		case args[i] == "--sums" && i+1 < len(args):
			sums = args[i+1]
			i++
		default:
			fmt.Fprintln(stderr, "usage: keel import [--force] [--sums FILE]")
			return exitUsage
		}
	}
	root, err := os.Getwd()
	if err != nil {
		fmt.Fprintf(stderr, "keel: %v\n", err)
		return exitConfig
	}
	path := filepath.Join(root, config.File)
	if _, err := os.Stat(path); err == nil && !force {
		fmt.Fprintf(stderr, "keel: %s already exists - pass --force to overwrite it\n", config.File)
		return exitConfig
	}
	c := importer.Import(root, version)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		fmt.Fprintf(stderr, "keel: %v\n", err)
		return exitConfig
	}
	if err := os.WriteFile(path, []byte(importer.Render(c)), 0o644); err != nil {
		fmt.Fprintf(stderr, "keel: %v\n", err)
		return exitConfig
	}
	if sums != "" {
		m, err := importer.ReadSums(sums)
		if err != nil {
			fmt.Fprintf(stderr, "keel: %v\n", err)
			return exitConfig
		}
		if err := os.WriteFile(filepath.Join(root, config.LockFile), []byte(importer.RenderLock(version, m)), 0o644); err != nil {
			fmt.Fprintf(stderr, "keel: %v\n", err)
			return exitConfig
		}
	}
	fmt.Fprintf(stdout, "keel: wrote %s (%d sensors)\n", config.File, len(c.Sensors))
	return 0
}
