# keel CLI — F1 Engine Core: Implementation Plan

> **Execution gate — read this first.** Do not start Task 1 until an ADR in the repository's ADR
> folder (`docs/adr/`, or the folder `.agents/state.yml` names as `ADR_DIR`) cites
> `docs/specs/2026-10-24-keel-cli-design.md` and records **which trigger of its §4 was met**: (1) keel runs in enough repositories
> that re-copying engine fixes costs more than distributing a binary; (2) `doctor` reports engine
> drift as a recurring finding; (3) the owner can require the binary everywhere the gate runs. The
> same ADR must supersede, for repositories that choose the CLI engine, the v0.3 portability policy
> (`2026-10-23-keel-harness-v0.3-design.md` §2.3, "the core must run with no agent at all") and D5
> (Copilot, Devin), because the binary-only end state (decision 5) runs only where keel is
> installed. Without that ADR, stop and report.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking. Follow the steps in order; each task starts with a failing test.

**Goal:** Phase F1 of the keel CLI: a Go binary, `keel`, that runs the existing sensor files from a
declarative `.agents/keel.yaml` while keeping the sensor contract byte for byte, ships `guard` as its
one native sensor, and proves compatibility by running the existing test suite through `keel gate`.

**Architecture:** A Go module in `cli/keel/`, outside `plugins/`, so the plugin is untouched until F4.
`internal/config` reads and validates `keel.yaml` and checks the pin against `.agents/keel.lock`;
`internal/gate` computes `SCOPE`, runs `exec:` sensors as `bash <file>` from the repository root with
stderr merged, and renders `gate.sh`'s report; `internal/guard` ports `guard.sh` (D32) and extends it
to `keel.yaml`, reading rule env files through `internal/envfile` (D33 semantics, nothing executed);
`internal/importer` writes `keel.yaml` and `keel.lock` from a bash-engine install. The test suite
gains `KEEL_ENGINE=cli`, which routes every gate through `keel gate` and every sensor through
`keel gate --sensor <id>`.

**Tech stack:** Go 1.27.3 (pinned with `GOTOOLCHAIN`), `go.yaml.in/yaml/v3` v3.0.5 (the YAML
organization's maintained fork; `gopkg.in/yaml.v3` was archived on 2025-04-01), the Go standard
library; bash 3.2-compatible test scripts; git.

**Spec:** `docs/specs/2026-10-24-keel-cli-design.md` (all of it); `docs/specs/2026-10-23-keel-harness-v0.3-design.md`
D32, D33, D39, D45, D48; `plugins/keel-harness/skills/build/references/sensor-contract.md`, the
contract kept byte for byte. Read them before Task 1.

**Provenance:** every file and patch below was prototyped on 2026-10-24 outside this repository, in
a scratch clone, first at F0 tasks 1–4 (`abf09a1`) and then at F0 complete (`abf09a1` plus F0
tasks 5–6 applied from the F0 plan). On F0 complete: `./tests/run.sh` → 1034 `ok` (991 + 43), rc 0;
`KEEL_ENGINE=cli ./tests/run.sh` → 1033 `ok` plus 1 `skip (cli)` (991 + 42), rc 0; `go vet` and
`go test` pass; `make dist` is byte-identical after `go clean -cache`. This document was then
checked by extracting every file and patch from it into a fresh clone at F0 complete and replaying
Tasks 1–5: every expected output matched, and `make dist` produced the same bytes as the prototype.
Copy the content **verbatim**. If a step's output differs from the expected output
written here, stop and report instead of improvising.

## Decisions (owner, 2026-10-24, in question rounds)

| # | Question (spec §7 or a gap found while planning) | Decision |
| --- | --- | --- |
| 1 | Implementation language | **Go**: a static binary with no runtime; startup measured at 2 ms (Python 14 ms, Node 24 ms) |
| 2 | Distribution | **Embedded in the plugin, outside `bin/`** (`plugins/keel-harness/engine/<os>-<arch>/keel`, in F4); `build` copies the right binary and checks its sha256. CI stays in this monorepo only: tests, parity, reproducible builds |
| 3 | Config format | **YAML**, with a published JSON Schema; decoded strictly |
| 4 | Where `keel.yaml` lives | **`.agents/keel.yaml`** |
| 5 | End state of the entry points | **Binary-only**: no keel script left in a target repository; the Makefile keeps **one-line aliases** (`gate-fast:` → `keel gate fast`) |
| 6 | Sensor list in phase 1 | **Explicit** in `keel.yaml`, `exec:` sensors included; the budgets move from `.agents/gate.env` into `keel.yaml` |
| 7 | Pin | **Exact version** in `keel.yaml` (`requires: 0.1.0`) plus **`.agents/keel.lock`** (sha256 per platform); no self-dispatch to other versions — **the pin follows the plugin** |
| 8 | Where the CLI source lives | **`cli/keel/` in this monorepo**; tags `cli/keel/vX.Y.Z` |
| 9 | `guard` and `keel.yaml` | **`keel guard` is native in F1**, ported from `guard.sh` and extended to `keel.yaml` |
| 10 | `run:` of native adapters (F3) | **An argv list, no shell**; `{scope}` expands to one argument per file |
| 11 | First native adapter (F3) | **`eslint-json`** |
| 12 | Phases and depth | **F1 core → F2 native entry points → F3 adapters, one at a time → F4 plugin integration**; only F1 is detailed here |

## Builder decisions (revisable; each is pinned by a test)

| Decision | Why | Pinned by |
| --- | --- | --- |
| Exit 3 for every `keel.yaml`, lock or pin problem; 64 for bad usage | Never a pass; the Stop hook already reports any exit outside {0,1} as "could not run" | `keel_cli_test.sh` |
| `keel gate --sensor <id>` runs one sensor with `SCOPE` as given (not recomputed) and prints its raw contract output | The existing sensor tests can then run through `keel gate` unchanged | `keel_cli_test.sh`, Task 4 |
| `keel import` writes `keel.yaml` (and, with `--sums`, `keel.lock`) from a bash-engine install; `guard.sh` becomes `adapter: guard` | The migration path F4's `build` will use; the test suite's CLI mode uses it on every run | `keel_cli_test.sh`, Task 4 |
| An installed harness (`.agents/state.yml` present) must list `adapter: guard` in the fast gate | The gate cannot see its own guard being dropped — a hole the bash engine shares when `guard.sh` is disabled; the explicit list makes it a validation error | `keel_cli_test.sh` |
| `guard` compares budgets and the sensor set across engines (base from `gate.env`/files when the base has no `keel.yaml`) | Switching engines must not be a way to loosen the harness | `keel_cli_test.sh` |
| An `exec:` sensor's class comes from its line 1, as in `gate.sh`; `keel.yaml` has no `class` for it | One source per fact | parity |
| Sensors run in `"<id>.sh"` byte order; ids are any file name `gate.sh` would run | `gate.sh` globbed `scripts/sensors/*.sh`; the parity test caught a stricter id rule that rejected a non-ASCII file name | parity |
| The lock check hashes the running binary | It catches a wrong build (a `go install` with the same version string), not a malicious binary, which could lie | `keel_cli_test.sh` |
| The JSON Schema serves editors; `keel validate` is the authority; a Go test keeps the schema's properties equal to the struct fields | No JSON Schema dependency | `config_test.go` |
| The test-only `scripts/gate.sh` shim exists only under `KEEL_ENGINE=cli`; F1 ships no shim | Decision 5: nothing transitional is shipped | Task 4 |

## Known differences from the bash engine (intentional)

1. **Order in non-C locales.** `gate.sh`'s glob and `sort -u` follow `LC_COLLATE`; `keel` orders bytewise. They agree under `C`/`POSIX` (the parity test runs with `LC_ALL=C`). A sensor must not depend on the order of `SCOPE`.
2. **`guard` needs no `scripts/lib/envparse.sh`.** The one assertion about that (`missing envparse lib: skip`) runs only on the bash engine (`bash_only`).
3. **Budget messages name the key of the file that holds it.** `gate.fast.ceiling_seconds raised from 30 to 300` for `keel.yaml`, `CEILING_SECONDS raised …` for `gate.env`.
4. **`guard.sh`'s `env_get` falls back to the process environment** for a key absent from a file; the port does not (no rule key is an environment variable).
5. **Unicode marks** (TTY only): `keel` reads `LC_ALL`/`LC_CTYPE`/`LANG` where `gate.sh` asked `locale charmap`.

## Global constraints

- Code, comments, docs and commit messages in **English**.
- **Nothing under `plugins/` changes in F1.** `git diff --stat <base> -- plugins/` stays empty; the installed bash engine and `./tests/run.sh` on it stay green.
- The CLI makes **no network call and no model call** at gate time; its only dependency outside the standard library is `go.yaml.in/yaml/v3` v3.0.5.
- Builds use `CGO_ENABLED=0 -trimpath -buildvcs=false -ldflags '-s -w -buildid=…'` and `GOTOOLCHAIN=go1.27.3`, so `make dist` is byte-reproducible (F4 commits the binaries and CI compares them).
- **Git:** work on the branch you were given; one commit per task with the message shown; push after each commit; **never open a pull request without the owner's explicit approval**.
- Do not bump any plugin version. Do not start F2: stop after Task 6 and report.

## Prerequisites

| Check | Command | Expected |
| --- | --- | --- |
| The gating ADR exists | `grep -lE 'keel-cli-design\.md' docs/adr/*.md docs/decisions/*.md 2>/dev/null` | one file, naming the §4 trigger |
| F0 is merged | `test -f plugins/keel-harness/skills/build/assets/sensors/common/guard.sh && test -f plugins/keel-harness/skills/build/assets/lib/envparse.sh && test -f tests/keel_guard_test.sh && echo ok` | `ok` |
| Go | `go version` | any; `GOTOOLCHAIN=go1.27.3` in `cli/keel/Makefile` fetches 1.27.3 when it differs (network at build time only) |
| bash, git, jq, shellcheck | `bash --version; git --version; jq --version; shellcheck --version` | present (as for F0) |
| `claude` CLI | `claude --version` | present (`make validate`) |
| Baseline | `./tests/run.sh > /tmp/base.log; echo rc=$?; grep -cE '^\s+ok ' /tmp/base.log` | `rc=0` and a count **N** (991 at F0 complete). Every expected count below is written relative to N |

## Review focus

The inputs most likely to break a repository that switches engines, each with the test that pins it:

1. **A non-ASCII or long summary or id.** Bash's `printf` pads by bytes in every locale, Go's `fmt` by runes → `padRight`/`padLeft` count bytes. Pinned by `TestPaddingCountsBytesLikeBashPrintf` (Task 3) and the parity case "non-ASCII and long fields" (`ação`/`não`).
2. **A sensor file name `gate.sh` accepts.** `acentuação-longa-demais.sh` must run, not fail validation. Pinned by the same parity case.
3. **Output that bends the contract**: no TAB on line 1, empty output, stderr interleaved with stdout, an exit code other than 0/1/2, more than 40 lines. Pinned by the parity cases (Task 3).
4. **Loosening through the engine switch**: a budget raised while it moves from `gate.env` to `keel.yaml`; a sensor dropped from the list while its file moves to `disabled/`. Pinned by `keel_cli_test.sh` "engine switch …" and "an exec entry dropped …".
5. **The guard dropping itself** from `keel.yaml`. Pinned by `keel_cli_test.sh` "an installed harness cannot drop the guard entry".

## File map

| Path | Responsibility | Task |
| --- | --- | --- |
| `cli/keel/go.mod`, `go.sum` | module `github.com/aether-labs-org/plugins/cli/keel` | 1 |
| `cli/keel/schema/keel.schema.json` | JSON Schema of `keel.yaml` for editors | 1 |
| `cli/keel/internal/config/` | `keel.yaml` (strict parse, validation), `keel.lock`, the pin | 1 |
| `cli/keel/internal/envfile/` | `KEY=value` reader with `envparse.sh` semantics | 2 |
| `cli/keel/internal/guard/` | native `guard` (D32) over baselines, rules, budgets and sensors | 2 |
| `cli/keel/internal/gate/` | `SCOPE`, the `exec` runner, `gate.sh`'s report | 3 |
| `cli/keel/internal/importer/` | `keel.yaml` and `keel.lock` from a bash-engine install | 3 |
| `cli/keel/main.go`, `Makefile`, `README.md` | commands, exit codes, reproducible builds | 3 |
| `tests/keel_cli_test.sh`, `tests/keel_cli_parity_test.sh` | CLI behaviour; byte parity with `gate.sh` | 3 |
| `tests/keel_helpers.sh`, `tests/keel_run_sensor.sh`, 7 test files | `KEEL_ENGINE=cli` | 4 |
| `.github/workflows/validate.yml`, `Makefile`, `.gitignore` | CI on both engines, `make check-cli`, `cli/keel/dist/` ignored | 1, 5 |

---

## Task 1 — `internal/config`: `keel.yaml`, `keel.lock` and the pin

**Files:** create `cli/keel/go.mod`, `cli/keel/go.sum`, `cli/keel/schema/keel.schema.json`,
`cli/keel/internal/config/config_test.go`, `cli/keel/internal/config/config.go`; modify `.gitignore`.

**Interfaces — produces:** `config.File`, `config.LockFile`, `type Config{Version int; Requires string; Gate Gates; Sensors []Sensor}`,
`type Sensor{ID, Gate, Exec, Adapter string}`, `config.Adapters map[string]bool`, `Parse([]byte) (*Config, error)`,
`Load(root string) (*Config, error)`, `(*Config).Validate(root string) []error`, `(*Config).Ceiling(mode string) int`,
`(*Config).SensorsFor(mode string) []Sensor`, `(*Config).Find(id string) (Sensor, bool)`, `ReadLock(path string) (*Lock, error)`,
`Platform() string`, `CheckPin(root string, c *Config, running string) error`, `FileSHA256(path string) (string, error)`.

- [ ] **Step 1: the module and the schema.**

File `cli/keel/go.mod`:

````text
module github.com/aether-labs-org/plugins/cli/keel

go 1.27.3

require go.yaml.in/yaml/v3 v3.0.5
````

File `cli/keel/go.sum`:

````text
go.yaml.in/yaml/v3 v3.0.5 h1:N6y/pJk8buWs9NY5ERU2HSMfm+IuD/OtfdAnq6kESPw=
go.yaml.in/yaml/v3 v3.0.5/go.mod h1:HVTZu1O7/Vkt2N+BFy8Zza+lnLsABggaTM2ZpNIGuKg=
````

File `cli/keel/schema/keel.schema.json`:

````json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://github.com/aether-labs-org/plugins/blob/main/cli/keel/schema/keel.schema.json",
  "title": "keel.yaml",
  "description": "The sensors and budgets of a repository's keel gates (.agents/keel.yaml). keel validate is the authority; this schema serves editors.",
  "type": "object",
  "additionalProperties": false,
  "required": ["version", "requires", "gate", "sensors"],
  "properties": {
    "version": { "const": 1 },
    "requires": { "type": "string", "pattern": "^[0-9]+\\.[0-9]+\\.[0-9]+$", "description": "Exact keel version; must match .agents/keel.lock and the running binary." },
    "gate": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "fast": { "$ref": "#/$defs/budget" },
        "slow": { "$ref": "#/$defs/budget" }
      }
    },
    "sensors": { "type": "array", "items": { "$ref": "#/$defs/sensor" } }
  },
  "$defs": {
    "budget": {
      "type": "object",
      "additionalProperties": false,
      "properties": { "ceiling_seconds": { "type": "integer", "minimum": 1 } }
    },
    "sensor": {
      "type": "object",
      "additionalProperties": false,
      "required": ["id", "gate"],
      "properties": {
        "id": { "type": "string", "pattern": "^[^_/\\u0000-\\u001f\\u007f][^/\\u0000-\\u001f\\u007f]*$" },
        "gate": { "enum": ["fast", "slow"] },
        "exec": { "type": "string", "description": "A sensor file that obeys the sensor contract, run with bash from the repository root." },
        "adapter": { "enum": ["guard"] }
      },
      "oneOf": [ { "required": ["exec"] }, { "required": ["adapter"] } ]
    }
  }
}
````

  Append `cli/keel/dist/` as a new last line of `.gitignore`: build output is never committed.

- [ ] **Step 2: write the failing test.**

File `cli/keel/internal/config/config_test.go`:

````go
package config

import (
	"encoding/json"
	"os"
	"reflect"
	"sort"
	"strings"
	"testing"
)

func TestParseRejectsUnknownKeysAndWrongTypes(t *testing.T) {
	for _, bad := range []string{
		"version: 1\nrequires: 0.1.0\nbogus: 1\n",
		"version: 1\nrequires: 0.1.0\ngate: { fast: { ceiling_seconds: thirty } }\n",
		"version: 1\nrequires: 0.1.0\nsensors: [ { id: a, gate: fast, exec: a.sh, class: security } ]\n",
	} {
		if _, err := Parse([]byte(bad)); err == nil {
			t.Errorf("Parse(%q) = nil error, want one", bad)
		}
	}
}

func TestRequiresMustBeExact(t *testing.T) {
	for v, ok := range map[string]bool{"0.1.0": true, "1.2.3": true, ">=1.2,<2": false, "1.2": false, "v1.2.3": false} {
		c := &Config{Version: 1, Requires: v}
		if got := len(c.Validate(t.TempDir())) == 0; got != ok {
			t.Errorf("requires %q valid = %v, want %v", v, got, ok)
		}
	}
}

func TestSensorsForUsesGateShOrder(t *testing.T) {
	c := &Config{Sensors: []Sensor{{ID: "architecture", Gate: "fast"}, {ID: "architecture-grep", Gate: "fast"}, {ID: "s", Gate: "slow"}}}
	var ids []string
	for _, s := range c.SensorsFor("fast") {
		ids = append(ids, s.ID)
	}
	// gate.sh globbed scripts/sensors/*.sh: "architecture-grep.sh" < "architecture.sh" bytewise.
	if want := []string{"architecture-grep", "architecture"}; !reflect.DeepEqual(ids, want) {
		t.Errorf("SensorsFor(fast) = %v, want %v", ids, want)
	}
}

func TestCeilingDefaults(t *testing.T) {
	c := &Config{}
	if c.Ceiling("fast") != 30 || c.Ceiling("slow") != 600 {
		t.Errorf("defaults = %d/%d, want 30/600", c.Ceiling("fast"), c.Ceiling("slow"))
	}
}

func yamlKeys(v any) []string {
	var keys []string
	rt := reflect.TypeOf(v)
	for i := 0; i < rt.NumField(); i++ {
		keys = append(keys, strings.Split(rt.Field(i).Tag.Get("yaml"), ",")[0])
	}
	sort.Strings(keys)
	return keys
}

func TestSchemaMatchesStructs(t *testing.T) {
	data, err := os.ReadFile("../../schema/keel.schema.json")
	if err != nil {
		t.Fatal(err)
	}
	var s struct {
		Properties map[string]any `json:"properties"`
		Defs       map[string]struct {
			Properties map[string]any `json:"properties"`
		} `json:"$defs"`
	}
	if err := json.Unmarshal(data, &s); err != nil {
		t.Fatal(err)
	}
	keys := func(m map[string]any) []string {
		var k []string
		for x := range m {
			k = append(k, x)
		}
		sort.Strings(k)
		return k
	}
	for name, pair := range map[string][2][]string{
		"Config": {yamlKeys(Config{}), keys(s.Properties)},
		"Sensor": {yamlKeys(Sensor{}), keys(s.Defs["sensor"].Properties)},
		"Budget": {yamlKeys(Budget{}), keys(s.Defs["budget"].Properties)},
	} {
		if !reflect.DeepEqual(pair[0], pair[1]) {
			t.Errorf("%s fields %v != schema properties %v", name, pair[0], pair[1])
		}
	}
}
````

- [ ] **Step 3: run it.** `cd cli/keel && go test ./internal/config/`. Expected: `FAIL` with `undefined: Parse` (the package has no code yet).
- [ ] **Step 4: create the package.**

File `cli/keel/internal/config/config.go`:

````go
// Package config reads and validates .agents/keel.yaml and .agents/keel.lock.
package config

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strings"

	"go.yaml.in/yaml/v3"
)

const (
	File     = ".agents/keel.yaml"
	LockFile = ".agents/keel.lock"

	DefaultFastCeiling = 30
	DefaultSlowCeiling = 600
)

// Config is .agents/keel.yaml, schema version 1.
type Config struct {
	Version  int      `yaml:"version"`
	Requires string   `yaml:"requires"`
	Gate     Gates    `yaml:"gate"`
	Sensors  []Sensor `yaml:"sensors"`
}

type Gates struct {
	Fast Budget `yaml:"fast"`
	Slow Budget `yaml:"slow"`
}

type Budget struct {
	CeilingSeconds int `yaml:"ceiling_seconds"`
}

// Sensor is one entry of `sensors:`. Exactly one of Exec and Adapter is set.
type Sensor struct {
	ID      string `yaml:"id"`
	Gate    string `yaml:"gate"`
	Exec    string `yaml:"exec,omitempty"`
	Adapter string `yaml:"adapter,omitempty"`
}

// Adapters lists the built-in adapters this version knows.
var Adapters = map[string]bool{"guard": true}

var (
	exactVersion = regexp.MustCompile(`^[0-9]+\.[0-9]+\.[0-9]+$`)
	// Any file name gate.sh would run: not empty, no '/', no control character (a TAB or newline would
	// corrupt line 1 of the report), not starting with '_'.
	sensorID = regexp.MustCompile(`^[^_/\x00-\x1f\x7f][^/\x00-\x1f\x7f]*$`)
)

// Ceiling returns the budget in seconds for mode fast or slow.
func (c *Config) Ceiling(mode string) int {
	if mode == "slow" {
		if c.Gate.Slow.CeilingSeconds > 0 {
			return c.Gate.Slow.CeilingSeconds
		}
		return DefaultSlowCeiling
	}
	if c.Gate.Fast.CeilingSeconds > 0 {
		return c.Gate.Fast.CeilingSeconds
	}
	return DefaultFastCeiling
}

// SensorsFor returns the sensors of one gate, in the order gate.sh ran them: by "<id>.sh", bytewise.
func (c *Config) SensorsFor(mode string) []Sensor {
	var out []Sensor
	for _, s := range c.Sensors {
		if s.Gate == mode {
			out = append(out, s)
		}
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].ID+".sh" < out[j].ID+".sh" })
	return out
}

// Find returns the sensor with the given id.
func (c *Config) Find(id string) (Sensor, bool) {
	for _, s := range c.Sensors {
		if s.ID == id {
			return s, true
		}
	}
	return Sensor{}, false
}

// Parse decodes keel.yaml strictly: unknown keys and wrong types are errors.
func Parse(data []byte) (*Config, error) {
	var c Config
	dec := yaml.NewDecoder(bytes.NewReader(data))
	dec.KnownFields(true)
	if err := dec.Decode(&c); err != nil {
		if errors.Is(err, io.EOF) {
			return nil, fmt.Errorf("%s is empty", File)
		}
		return nil, fmt.Errorf("%s: %v", File, err)
	}
	return &c, nil
}

// Load reads and validates keel.yaml under root. It does not check the pin; see CheckPin.
func Load(root string) (*Config, error) {
	data, err := os.ReadFile(filepath.Join(root, File))
	if err != nil {
		return nil, fmt.Errorf("no %s - run keel import or /keel-harness:build", File)
	}
	c, err := Parse(data)
	if err != nil {
		return nil, err
	}
	if errs := c.Validate(root); len(errs) > 0 {
		return nil, errors.Join(errs...)
	}
	return c, nil
}

// Validate returns every problem found; nil when the file is usable.
func (c *Config) Validate(root string) []error {
	var errs []error
	add := func(format string, a ...any) { errs = append(errs, fmt.Errorf(File+": "+format, a...)) }
	if c.Version != 1 {
		add("version must be 1, got %d", c.Version)
	}
	if !exactVersion.MatchString(c.Requires) {
		add("requires must be an exact version such as 0.1.0 (ranges are not accepted), got %q", c.Requires)
	}
	if c.Gate.Fast.CeilingSeconds < 0 || c.Gate.Slow.CeilingSeconds < 0 {
		add("gate ceiling_seconds must be positive")
	}
	seen := map[string]bool{}
	for i, s := range c.Sensors {
		where := fmt.Sprintf("sensors[%d] (id %q)", i, s.ID)
		if !sensorID.MatchString(s.ID) {
			add("%s: id must be a file name without '/' or control characters, not starting with '_'", where)
		}
		if seen[s.ID] {
			add("%s: duplicate id", where)
		}
		seen[s.ID] = true
		if s.Gate != "fast" && s.Gate != "slow" {
			add("%s: gate must be fast or slow, got %q", where, s.Gate)
		}
		switch {
		case (s.Exec == "") == (s.Adapter == ""):
			add("%s: set exactly one of exec and adapter", where)
		case s.Adapter != "" && !Adapters[s.Adapter]:
			add("%s: unknown adapter %q", where, s.Adapter)
		case s.Exec != "":
			clean := filepath.ToSlash(filepath.Clean(s.Exec))
			if filepath.IsAbs(s.Exec) || strings.HasPrefix(clean, "../") || clean != s.Exec || strings.HasPrefix(s.Exec, "-") {
				add("%s: exec must be a clean path inside the repository, got %q", where, s.Exec)
			} else if st, err := os.Stat(filepath.Join(root, s.Exec)); err != nil || !st.Mode().IsRegular() {
				add("%s: exec file %s does not exist", where, s.Exec)
			}
			if strings.TrimSuffix(filepath.Base(s.Exec), ".sh") != s.ID {
				add("%s: id must equal the exec file name without .sh", where)
			}
		}
	}
	// The gate cannot notice its own guard being dropped, so an installed harness must list it.
	if _, err := os.Stat(filepath.Join(root, ".agents/state.yml")); err == nil {
		g, ok := c.Find("guard")
		if !ok || g.Adapter != "guard" || g.Gate != "fast" {
			add("an installed harness (.agents/state.yml) must list the guard sensor: `- id: guard`, `gate: fast`, `adapter: guard` (D32)")
		}
	}
	// A sensor file the gate would have run but keel.yaml does not list would never run: refuse.
	for _, dir := range []string{"scripts/sensors", "scripts/sensors/slow"} {
		files, _ := filepath.Glob(filepath.Join(root, dir, "*.sh"))
		for _, f := range files {
			id := strings.TrimSuffix(filepath.Base(f), ".sh")
			if strings.HasPrefix(id, "_") || seen[id] {
				continue
			}
			if st, err := os.Stat(f); err == nil && st.Mode().IsRegular() {
				add("%s/%s.sh is not listed under sensors:, so it would never run - list it or move it to scripts/sensors/disabled/", dir, id)
			}
		}
	}
	return errs
}

// Lock is .agents/keel.lock: the pinned version and the sha256 of each platform's binary.
type Lock struct {
	Version string
	Sums    map[string]string // "linux-amd64" -> hex sha256
}

// ReadLock parses a lock file: `#` comments, then TAB-separated `version<TAB>X` and `<os>-<arch><TAB><sha256>` rows.
func ReadLock(path string) (*Lock, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("no %s - run /keel-harness:build", LockFile)
	}
	defer f.Close()
	l := &Lock{Sums: map[string]string{}}
	sc := bufio.NewScanner(f)
	for n := 1; sc.Scan(); n++ {
		line := strings.TrimRight(sc.Text(), "\r")
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		k, v, ok := strings.Cut(line, "\t")
		if !ok {
			return nil, fmt.Errorf("%s:%d: expected KEY<TAB>VALUE", LockFile, n)
		}
		if k == "version" {
			l.Version = v
		} else {
			l.Sums[k] = v
		}
	}
	return l, sc.Err()
}

// Platform is the lock key of the running binary.
func Platform() string { return runtime.GOOS + "-" + runtime.GOARCH }

// CheckPin fails unless keel.yaml, keel.lock and the running binary agree: same version, and the
// binary's sha256 equals the lock row for this platform. A mismatch is a fail, never a warning.
func CheckPin(root string, c *Config, running string) error {
	if c.Requires != running {
		return fmt.Errorf("%s requires keel %s, but this is keel %s - run /keel-harness:build to align the pin", File, c.Requires, running)
	}
	l, err := ReadLock(filepath.Join(root, LockFile))
	if err != nil {
		return err
	}
	if l.Version != c.Requires {
		return fmt.Errorf("%s pins keel %s but %s requires %s - run /keel-harness:build", LockFile, l.Version, File, c.Requires)
	}
	want, ok := l.Sums[Platform()]
	if !ok {
		return fmt.Errorf("%s has no checksum for %s", LockFile, Platform())
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	got, err := FileSHA256(exe)
	if err != nil {
		return err
	}
	if got != want {
		return fmt.Errorf("this keel binary (%s) is not the build %s pins for %s - run /keel-harness:build", exe, LockFile, Platform())
	}
	return nil
}

// FileSHA256 returns the hex sha256 of a file.
func FileSHA256(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}
````

- [ ] **Step 5: run it.** `cd cli/keel && go vet ./... && go test ./internal/config/` → `ok  	github.com/aether-labs-org/plugins/cli/keel/internal/config`.
- [ ] **Step 6: commit and push.** `feat(keel-cli): keel.yaml and keel.lock with an exact, checksummed pin`

---

## Task 2 — `internal/envfile` and the native `guard`

**Files:** create `cli/keel/internal/envfile/envfile_test.go`, `envfile.go`, `cli/keel/internal/guard/guard_test.go`, `guard.go`.

**Interfaces — consumes:** `config.Parse`, `config.File`, `(*Config).Ceiling`. **Produces:** `envfile.Parse(name, data string) (map[string]string, error)`;
`guard.Run(root string) (out string, rc int)` (contract output, exit 0 or 1), `guard.Guidance`, `guard.ADRDirs`.

Behaviour of `guard.Run`, all relative to the base (`KEEL_GUARD_BASE`, else the merge-base with `origin/HEAD`, else `HEAD`), byte for byte as `guard.sh`:

| Loosening | Reported as |
| --- | --- |
| A TSV baseline row that grew or appeared; a native baseline with more lines | as `guard.sh` (`<file>: <path> <old> -> <new>`, `native baseline grew …`) |
| A relaxed `*MIN*`/`*LIMIT*`/`*MAX*`, a widened or narrowed list, a changed `ENFORCEMENT`, a deleted rule | as `guard.sh` |
| A raised budget, read from `keel.yaml` when the file exists (at the base and now, independently), else from `gate.env` | `<file>: <key> raised from <a> to <b>` with the key of that file |
| A sensor at the base (from `keel.yaml`, else from `scripts/sensors/{,slow/}*.sh`) missing now | `<exec path or .agents/keel.yaml>: sensor removed or disabled` |

A loosening passes only when an ADR added since the base in `docs/adr`, `doc/adr`, `docs/decisions` or `docs/architecture/decisions` contains the reported file's path. The full conformance suite for `guard` is `tests/keel_guard_test.sh` run on the CLI engine (Task 4); here the Go tests pin the helpers whose semantics come from awk and grep.

- [ ] **Step 1: write the failing tests.**

File `cli/keel/internal/envfile/envfile_test.go`:

````go
package envfile

import (
	"strings"
	"testing"
)

// The fixture of tests/keel_envparse_test.sh: the Go reader must agree with scripts/lib/envparse.sh.
const ok = "# Managed by keel-harness - see .agents/README.md\nRULE_ID=file-size\nKIND=metric                       # metric | structure\n  LIMIT=300\nINCLUDE='src/'\nLAYERS='domain|src/d|com.d||domainModels\nweb|src/w|com.w|domain|adapter'\nNOTE=\"it's fine\"   # trailing comment\nLITERAL=$HOME\nEMPTY=\nCRLF=yes\r\nLAST=noeol"

func TestParseMatchesEnvparse(t *testing.T) {
	got, err := Parse("ok.env", ok)
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]string{
		"RULE_ID": "file-size", "KIND": "metric", "LIMIT": "300", "INCLUDE": "src/",
		"LAYERS": "domain|src/d|com.d||domainModels\nweb|src/w|com.w|domain|adapter",
		"NOTE": "it's fine", "LITERAL": "$HOME", "EMPTY": "", "CRLF": "yes", "LAST": "noeol",
	}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("%s = %q, want %q", k, got[k], v)
		}
	}
}

func TestParseRejectsLikeEnvparse(t *testing.T) {
	for line, reason := range map[string]string{
		"X=$(touch PWNED)": "contains $( or a backtick", "X=`id`": "contains $( or a backtick",
		"X='open": "unterminated quote", "not a line": "not a KEY=value line", "lower=1": "not a KEY=value line",
		"X='a' junk": "unexpected text after the closing quote",
	} {
		_, err := Parse("bad.env", line+"\n")
		if err == nil || !strings.Contains(err.Error(), reason) || !strings.Contains(err.Error(), "bad.env:1:") {
			t.Errorf("Parse(%q) error = %v, want bad.env:1: ... %s", line, err, reason)
		}
	}
}
````

File `cli/keel/internal/guard/guard_test.go`:

````go
package guard

import "testing"

func TestAwkNum(t *testing.T) {
	for in, want := range map[string]float64{"20": 20, "20\r": 20, " 7": 7, "3abc": 3, "": 0, "x": 0, "1.5": 1.5, "+4": 4, "-2": -2} {
		if got := awkNum(in); got != want {
			t.Errorf("awkNum(%q) = %v, want %v", in, got, want)
		}
	}
}

func TestCountLinesIgnoresBlankLines(t *testing.T) {
	if got := countLines("a\n  \n\tb\n"); got != 2 {
		t.Errorf("countLines = %d, want 2", got)
	}
}
````

- [ ] **Step 2: run them.** `cd cli/keel && go test ./internal/envfile/ ./internal/guard/`. Expected: `FAIL` for both packages, `undefined: Parse` and `undefined: awkNum`.
- [ ] **Step 3: create the packages.**

File `cli/keel/internal/envfile/envfile.go`:

````go
// Package envfile reads KEY=value files without executing anything, with the semantics of
// scripts/lib/envparse.sh (keel_env_load): comments, unquoted values with a trailing ` # comment`,
// single- or double-quoted values that may span lines, CRLF tolerated, nothing expanded, and a
// value containing `$(` or a backtick rejected.
package envfile

import (
	"fmt"
	"strings"
)

const space = " \t\n\v\f\r"

// Parse returns every KEY=value of data. name is used in error messages only.
func Parse(name, data string) (map[string]string, error) {
	vals := map[string]string{}
	lines := strings.Split(data, "\n")
	if strings.HasSuffix(data, "\n") {
		lines = lines[:len(lines)-1]
	}
	var key, q, buf string
	open, start := false, 0
	set := func(n int, k, v string) error {
		if strings.Contains(v, "$(") || strings.Contains(v, "`") {
			return fmt.Errorf("%s:%d: %s contains $( or a backtick, which keel never executes", name, n, k)
		}
		vals[k] = v
		return nil
	}
	tail := func(n int, rest string) error {
		t := strings.TrimLeft(rest, space)
		if t == "" || strings.HasPrefix(t, "#") {
			return nil
		}
		return fmt.Errorf("%s:%d: unexpected text after the closing quote", name, n)
	}
	for i, line := range lines {
		n := i + 1
		line = strings.TrimSuffix(line, "\r")
		if open {
			if j := strings.Index(line, q); j >= 0 {
				buf += "\n" + line[:j]
				if err := tail(n, line[j+1:]); err != nil {
					return nil, err
				}
				if err := set(start, key, buf); err != nil {
					return nil, err
				}
				open = false
			} else {
				buf += "\n" + line
			}
			continue
		}
		t := strings.TrimLeft(line, space)
		if t == "" || strings.HasPrefix(t, "#") {
			continue
		}
		eq := strings.Index(t, "=")
		key = ""
		if eq > 0 {
			key = t[:eq]
		}
		if !validKey(key) {
			return nil, fmt.Errorf("%s:%d: not a KEY=value line (keys are UPPER_CASE)", name, n)
		}
		rest := t[eq+1:]
		if strings.HasPrefix(rest, "'") || strings.HasPrefix(rest, `"`) {
			q, rest = rest[:1], rest[1:]
			if j := strings.Index(rest, q); j >= 0 {
				if err := tail(n, rest[j+1:]); err != nil {
					return nil, err
				}
				if err := set(n, key, rest[:j]); err != nil {
					return nil, err
				}
			} else {
				open, start, buf = true, n, rest
			}
			continue
		}
		// ${rest%%[[:space:]]#*}: cut at the first blank that is followed by '#', then trim the right.
		for j := 0; j+1 < len(rest); j++ {
			if strings.IndexByte(space, rest[j]) >= 0 && rest[j+1] == '#' {
				rest = rest[:j]
				break
			}
		}
		if err := set(n, key, strings.TrimRight(rest, space)); err != nil {
			return nil, err
		}
	}
	if open {
		return nil, fmt.Errorf("%s:%d: %s has an unterminated quote", name, start, key)
	}
	return vals, nil
}

func validKey(k string) bool {
	if k == "" || (k[0] >= '0' && k[0] <= '9') {
		return false
	}
	for i := 0; i < len(k); i++ {
		c := k[i]
		if !(c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '_') {
			return false
		}
	}
	return true
}
````

File `cli/keel/internal/guard/guard.go`:

````go
// Package guard is the native port of scripts/sensors/guard.sh (D32), extended to keel.yaml: it fails
// when the harness was loosened since the base commit unless an ADR added in this change names the
// loosened file. Its output obeys the sensor contract byte for byte.
package guard

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/aether-labs-org/plugins/cli/keel/internal/config"
	"github.com/aether-labs-org/plugins/cli/keel/internal/envfile"
)

const (
	id       = "guard"
	class    = "security"
	Guidance = "undo the loosening and fix the code instead. If loosening is really the decision, add an ADR in this same change that names each file listed above and says why. Editing, deleting or disabling this sensor is the wrong fix."
)

// ADRDirs are the folders read for ADRs added in the change (guard.sh's ADR_DIRS).
var ADRDirs = []string{"docs/adr", "doc/adr", "docs/decisions", "docs/architecture/decisions"}

type finding struct{ file, what string }

type repo struct{ root string }

func (r repo) git(args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = r.root
	out, err := cmd.Output()
	return string(out), err
}

func (r repo) atBase(base, path string) (string, bool) {
	out, err := r.git("show", base+":"+path)
	return out, err == nil
}

func (r repo) read(path string) (string, bool) {
	b, err := os.ReadFile(filepath.Join(r.root, path))
	return string(b), err == nil
}

func line1(status, summary string) string {
	return fmt.Sprintf("%s\t%s\t%s\t%s\n", id, class, status, summary)
}

// Run returns guard's contract output and exit code (0 pass, 1 fail).
func Run(root string) (string, int) {
	r := repo{root}
	if _, err := r.git("rev-parse", "--verify", "-q", "HEAD"); err != nil {
		return line1("pass", "No commits yet - nothing to compare."), 0
	}
	base := os.Getenv("KEEL_GUARD_BASE")
	if base == "" {
		if _, err := r.git("rev-parse", "--verify", "-q", "refs/remotes/origin/HEAD"); err == nil {
			mb, _ := r.git("merge-base", "HEAD", "refs/remotes/origin/HEAD")
			base = strings.TrimSpace(mb)
		}
	}
	if base == "" {
		base = "HEAD"
	}
	s, err := r.git("rev-parse", "--short", base)
	if err != nil {
		return line1("fail", "KEEL_GUARD_BASE="+base+" is not a commit.") +
			"  guidance: Set KEEL_GUARD_BASE to the branch the change will merge into (e.g. origin/main), or unset it.\n", 1
	}
	short := strings.TrimSpace(s)
	if _, err := r.git("cat-file", "-e", base+":.agents/state.yml"); err != nil {
		return line1("pass", "Harness installed in this change - nothing to compare (base "+short+")."), 0
	}

	var loose []finding
	add := func(f, w string) { loose = append(loose, finding{f, w}) }
	baselines(r, base, add)
	rules(r, base, add)
	budgets(r, base, add)
	sensors(r, base, add)

	adrs := addedADRs(r, base)
	var left []string
	covered := 0
	for _, l := range loose {
		if namedBy(r, adrs, l.file) {
			covered++
		} else {
			left = append(left, l.file+": "+l.what)
		}
	}
	if len(left) == 0 {
		if covered > 0 {
			return line1("pass", fmt.Sprintf("%d loosening(s) since %s, each named by an ADR added in this change.", covered, short)), 0
		}
		return line1("pass", "No harness file loosened since "+short+"."), 0
	}
	var b strings.Builder
	b.WriteString(line1("fail", fmt.Sprintf("%d loosening(s) of the harness since %s without an ADR.", len(left), short)))
	for i, l := range left {
		if i == 5 {
			break
		}
		b.WriteString("  " + l + "\n")
	}
	b.WriteString("  guidance: " + Guidance + "\n")
	return b.String(), 1
}

func nonEmptyLines(s string) []string {
	var out []string
	for _, l := range strings.Split(s, "\n") {
		if l != "" {
			out = append(out, l)
		}
	}
	return out
}

var awkNumber = regexp.MustCompile(`^[ \t\n\v\f\r]*[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?`)

// awkNum is awk's `$2 + 0`: the longest numeric prefix, 0 when there is none.
func awkNum(s string) float64 {
	m := strings.TrimLeft(awkNumber.FindString(s), " \t\n\v\f\r")
	v, _ := strconv.ParseFloat(m, 64)
	return v
}

// tsvRows yields (path, count) for each line that is not a comment and has at least two TAB fields.
func tsvRows(s string, fn func(path, count string)) {
	lines := strings.Split(s, "\n")
	if strings.HasSuffix(s, "\n") {
		lines = lines[:len(lines)-1]
	}
	for _, l := range lines {
		if strings.HasPrefix(l, "#") {
			continue
		}
		f := strings.Split(l, "\t")
		if len(f) >= 2 {
			fn(f[0], f[1])
		}
	}
}

// 1. Baselines: a TSV row whose count grew or appeared; any other file (native store) with more lines.
func baselines(r repo, base string, add func(string, string)) {
	a, _ := r.git("ls-tree", "-r", "--name-only", base, "--", ".agents/baselines/")
	b, _ := r.git("ls-files", "--cached", "--others", "--exclude-standard", "--", ".agents/baselines/")
	set := map[string]bool{}
	for _, f := range nonEmptyLines(a + "\n" + b) {
		set[f] = true
	}
	files := make([]string, 0, len(set))
	for f := range set {
		files = append(files, f)
	}
	sort.Strings(files)
	for _, f := range files {
		old, _ := r.atBase(base, f)
		cur, _ := r.read(f)
		cur = strings.ReplaceAll(cur, "\r", "")
		if strings.HasSuffix(f, ".tsv") {
			prev := map[string]float64{}
			tsvRows(old, func(p, c string) { prev[p] = awkNum(c) })
			tsvRows(cur, func(p, c string) {
				o := prev[p]
				if n := awkNum(c); n > o {
					add(f, fmt.Sprintf("%s %d -> %d", p, int64(o), int64(n)))
				}
			})
			continue
		}
		if o, n := len(nonEmptyLines(old)), len(nonEmptyLines(cur)); n > o {
			add(f, fmt.Sprintf("native baseline grew from %d to %d lines", o, n))
		}
	}
}

var envKey = regexp.MustCompile(`^[ \t\n\v\f\r]*([A-Z_][A-Z0-9_]*)=`)

// envGet mirrors guard.sh's env_get: a file that does not parse yields "" for every key.
func envGet(name, data, key string) string {
	vals, err := envfile.Parse(name, data)
	if err != nil {
		return ""
	}
	return vals[key]
}

func isNum(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return true
}

func atoi(s string) int64 { n, _ := strconv.ParseInt(s, 10, 64); return n }

// countLines is `grep -c '[^[:space:]]'`: lines with at least one non-blank character.
func countLines(s string) int {
	n := 0
	for _, l := range strings.Split(s, "\n") {
		if strings.TrimLeft(l, " \t\v\f\r") != "" {
			n++
		}
	}
	return n
}

// 2. Rule env files: relaxed limits, widened lists, changed enforcement, deleted rules.
func rules(r repo, base string, add func(string, string)) {
	ls, _ := r.git("ls-tree", "--name-only", base, "--", ".agents/rules/")
	for _, f := range nonEmptyLines(ls) {
		if !strings.HasSuffix(f, ".env") {
			continue
		}
		cur, ok := r.read(f)
		if !ok {
			add(f, "rule deleted")
			continue
		}
		old, _ := r.atBase(base, f)
		keys := map[string]bool{}
		for _, src := range []string{old, cur} {
			for _, l := range strings.Split(src, "\n") {
				if m := envKey.FindStringSubmatch(l); m != nil {
					keys[m[1]] = true
				}
			}
		}
		sorted := make([]string, 0, len(keys))
		for k := range keys {
			sorted = append(sorted, k)
		}
		sort.Strings(sorted)
		for _, k := range sorted {
			o, n := envGet(f, old, k), envGet(f, cur, k)
			if o == n {
				continue
			}
			switch {
			case strings.Contains(k, "MIN"):
				if isNum(o) && isNum(n) && atoi(n) < atoi(o) {
					add(f, fmt.Sprintf("%s lowered from %s to %s", k, o, n))
				}
			case strings.Contains(k, "LIMIT") || strings.Contains(k, "MAX"):
				if isNum(o) && isNum(n) && atoi(n) > atoi(o) {
					add(f, fmt.Sprintf("%s raised from %s to %s", k, o, n))
				}
			case k == "ALLOWED" || k == "EXCLUDE" || k == "IGNORE_IMPORTS":
				if countLines(n) > countLines(o) {
					add(f, k+" widened")
				}
			case k == "INCLUDE" || k == "FORBIDDEN":
				if countLines(n) < countLines(o) {
					add(f, k+" narrowed")
				}
			case k == "ENFORCEMENT":
				add(f, fmt.Sprintf("ENFORCEMENT changed from '%s' to '%s'", o, n))
			}
		}
	}
}

// budget is one ceiling as read from keel.yaml or gate.env.
type budget struct {
	file, key, value string
}

// budgetsOf reads the fast and slow ceilings from keel.yaml when it exists, else from gate.env.
func budgetsOf(yamlData string, yamlOK bool, envData string, envOK bool) ([]budget, bool) {
	if yamlOK {
		if c, err := config.Parse([]byte(yamlData)); err == nil {
			return []budget{
				{config.File, "gate.fast.ceiling_seconds", strconv.Itoa(c.Ceiling("fast"))},
				{config.File, "gate.slow.ceiling_seconds", strconv.Itoa(c.Ceiling("slow"))},
			}, true
		}
	}
	if envOK {
		return []budget{
			{".agents/gate.env", "CEILING_SECONDS", envGet(".agents/gate.env", envData, "CEILING_SECONDS")},
			{".agents/gate.env", "SLOW_CEILING_SECONDS", envGet(".agents/gate.env", envData, "SLOW_CEILING_SECONDS")},
		}, true
	}
	return nil, false
}

// 3. Gate budgets, wherever they live at the base and now (an engine switch moves them).
func budgets(r repo, base string, add func(string, string)) {
	by, byOK := r.atBase(base, config.File)
	be, beOK := r.atBase(base, ".agents/gate.env")
	ny, nyOK := r.read(config.File)
	ne, neOK := r.read(".agents/gate.env")
	old, ok1 := budgetsOf(by, byOK, be, beOK)
	cur, ok2 := budgetsOf(ny, nyOK, ne, neOK)
	if !ok1 || !ok2 {
		return
	}
	for i := range cur {
		o, n := old[i].value, cur[i].value
		if isNum(o) && isNum(n) && atoi(n) > atoi(o) {
			add(cur[i].file, fmt.Sprintf("%s raised from %s to %s", cur[i].key, o, n))
		}
	}
}

// sensorSet maps "gate/id" to the file a reviewer must name: the exec path, or keel.yaml itself.
type sensorSet struct {
	keys   []string
	labels map[string]string
}

func fromConfig(data string) (sensorSet, bool) {
	c, err := config.Parse([]byte(data))
	if err != nil {
		return sensorSet{}, false
	}
	s := sensorSet{labels: map[string]string{}}
	for _, e := range c.Sensors {
		k := e.Gate + "/" + e.ID
		label := config.File
		if e.Exec != "" {
			label = e.Exec
		}
		s.keys = append(s.keys, k)
		s.labels[k] = label
	}
	return s, true
}

func fromFiles(paths []string) sensorSet {
	s := sensorSet{labels: map[string]string{}}
	for _, p := range paths {
		if !strings.HasSuffix(p, ".sh") || strings.HasPrefix(filepath.Base(p), "_") {
			continue
		}
		dir := filepath.Dir(p)
		if dir != "scripts/sensors" && dir != "scripts/sensors/slow" {
			continue
		}
		gate := "fast"
		if dir == "scripts/sensors/slow" {
			gate = "slow"
		}
		k := gate + "/" + strings.TrimSuffix(filepath.Base(p), ".sh")
		s.keys = append(s.keys, k)
		s.labels[k] = p
	}
	return s
}

// 4. Sensors removed, disabled or dropped from keel.yaml since the base.
func sensors(r repo, base string, add func(string, string)) {
	var old sensorSet
	data, ok := r.atBase(base, config.File)
	if ok {
		old, ok = fromConfig(data)
	}
	if !ok {
		ls, _ := r.git("ls-tree", "--name-only", base, "--", "scripts/sensors/", "scripts/sensors/slow/")
		old = fromFiles(nonEmptyLines(ls))
	}
	var cur sensorSet
	data, ok = r.read(config.File)
	if ok {
		cur, ok = fromConfig(data)
	}
	if !ok {
		var paths []string
		for _, d := range []string{"scripts/sensors", "scripts/sensors/slow"} {
			m, _ := filepath.Glob(filepath.Join(r.root, d, "*.sh"))
			for _, f := range m {
				if st, err := os.Stat(f); err == nil && st.Mode().IsRegular() {
					paths = append(paths, d+"/"+filepath.Base(f))
				}
			}
		}
		cur = fromFiles(paths)
	}
	for _, k := range old.keys {
		if _, ok := cur.labels[k]; !ok {
			add(old.labels[k], "sensor removed or disabled")
		}
	}
}

func addedADRs(r repo, base string) []string {
	set := map[string]bool{}
	for _, d := range ADRDirs {
		a, _ := r.git("diff", "--name-only", "--diff-filter=A", base, "--", d)
		b, _ := r.git("ls-files", "--others", "--exclude-standard", "--", d)
		for _, f := range nonEmptyLines(a + "\n" + b) {
			set[f] = true
		}
	}
	out := make([]string, 0, len(set))
	for f := range set {
		out = append(out, f)
	}
	sort.Strings(out)
	return out
}

func namedBy(r repo, adrs []string, file string) bool {
	for _, a := range adrs {
		if b, ok := r.read(a); ok && strings.Contains(b, file) {
			return true
		}
	}
	return false
}
````

- [ ] **Step 4: run them.** `cd cli/keel && go vet ./... && go test ./...` → `ok` for `config`, `envfile` and `guard`.
- [ ] **Step 5: commit and push.** `feat(keel-cli): native guard over baselines, rules, budgets and the sensor set (D32)`

---

## Task 3 — the `keel` binary: gate, import, commands, and byte parity with `gate.sh`

**Files:** create `cli/keel/internal/gate/gate_test.go`, `gate.go`, `cli/keel/internal/importer/importer_test.go`, `importer.go`,
`cli/keel/main.go`, `cli/keel/Makefile`, `cli/keel/README.md`, `tests/keel_cli_test.sh`, `tests/keel_cli_parity_test.sh`.

**Interfaces — consumes:** Tasks 1–2. **Produces:** the commands `keel version | validate | gate [fast|slow] | gate --sensor <id> | measure <id> | guard | import [--force] [--sums FILE]`
with exits 0/1 (gate), the sensor's own code (`--sensor`, `measure`), 3 (configuration or pin), 64 (usage);
`make -C cli/keel build` → `cli/keel/dist/keel` and `cli/keel/dist/SHA256SUMS` (rows `<sha256>  <os>-<arch>/keel`);
`make -C cli/keel dist` → `cli/keel/dist/engine/<os>-<arch>/keel` and `cli/keel/dist/engine/SHA256SUMS` for linux/darwin × amd64/arm64.

Byte parity means: on the same repository and with `LC_ALL=C`, `bash scripts/gate.sh` and `keel gate` exit with the same code and print the same report and the same `.agents/last-run*.log`, **after replacing only the per-sensor time column and the `spent` value**. The bash tests skip locally when the binary is not built and fail under `CI`.

- [ ] **Step 1: write the failing tests.**

File `cli/keel/internal/gate/gate_test.go`:

````go
package gate

import "testing"

func TestCutFieldMimicsCut(t *testing.T) {
	cases := []struct {
		line string
		n    int
		want string
	}{
		{"a\tb\tc\td", 2, "b"}, {"a\tb\tc\td", 4, "d"}, {"a\tb", 4, ""}, {"no tabs here", 2, "no tabs here"}, {"", 2, ""},
	}
	for _, c := range cases {
		if got := cutField(c.line, c.n); got != c.want {
			t.Errorf("cutField(%q, %d) = %q, want %q", c.line, c.n, got, c.want)
		}
	}
}

func TestPaddingCountsBytesLikeBashPrintf(t *testing.T) {
	if got := padRight("ação", 12); got != "ação      " || len(got) != 12 {
		t.Errorf("padRight = %q (%d bytes), want 12 bytes", got, len(got))
	}
	if got := padLeft("12ms", 8); got != "    12ms" {
		t.Errorf("padLeft = %q", got)
	}
	if got := padRight("longer than twelve", 12); got != "longer than twelve" {
		t.Errorf("padRight must not truncate, got %q", got)
	}
}

func TestDuration(t *testing.T) {
	for ms, want := range map[int64]string{0: "0ms", 999: "999ms", 1000: "1.0s", 1234: "1.2s", 61999: "61.9s"} {
		if got := duration(ms); got != want {
			t.Errorf("duration(%d) = %q, want %q", ms, got, want)
		}
	}
}

func TestRunStateIsExcludedFromScope(t *testing.T) {
	for p, excluded := range map[string]bool{
		".agents/last-run.log": true, ".agents/last-seen": true, ".agents/.gate-lock/x": true,
		".agents/notes.md": false, ".agents/keel.yaml": false, "src/last-run.log": false,
	} {
		if got := runState.MatchString(p); got != excluded {
			t.Errorf("runState(%q) = %v, want %v", p, got, excluded)
		}
	}
}
````

File `cli/keel/internal/importer/importer_test.go`:

````go
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
````

File `tests/keel_cli_test.sh`:

````bash
#!/usr/bin/env bash
# keel CLI behaviour that has no bash-engine counterpart: keel.yaml validation, the pin and the lock,
# import, single-sensor runs, and guard over keel.yaml.
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
BIN="${KEEL_BIN:-$(cd "$(dirname "$0")/.." && pwd)/cli/keel/dist/keel}"
SUMS="$(dirname "$BIN")/SHA256SUMS"
if [ ! -x "$BIN" ]; then
  if [ -n "${CI:-}" ]; then fail "keel CLI not built (make -C cli/keel build is required in CI)"; finish; fi
  echo "  skip keel CLI: $BIN not built (make -C cli/keel build)"; exit 0
fi
k() { out="$(cd "$r" && "$BIN" "$@" 2>&1)"; rc=$?; }
has() { printf '%s\n' "$out" | grep -qF -- "$1"; }

# mk -> committed repo with one exec sensor, guard, state.yml, keel.yaml and keel.lock imported
mk() {
  r="$(new_repo)"
  mkdir -p "$r/scripts/sensors" "$r/.agents" "$r/docs/adr"
  printf '#!/usr/bin/env bash\nprintf "lint\\theuristic\\tpass\\tok\\n"\n[ "${KEEL_MEASURE:-}" = 1 ] && echo measured\nprintf "%%s" "$SCOPE" > scope.out\n' > "$r/scripts/sensors/lint.sh"
  cp "$KEEL/skills/build/assets/sensors/common/guard.sh" "$r/scripts/sensors/guard.sh"
  printf 'schema_version: 2\n' > "$r/.agents/state.yml"
  # As /keel-harness:build will: a wrapper replaced by a native adapter leaves the repository.
  (cd "$r" && "$BIN" import --sums "$SUMS" >/dev/null && rm scripts/sensors/guard.sh && git add -A && git commit -qm harness)
}
yaml_set() { sed -i "$1" "$r/.agents/keel.yaml"; }

mk; k version; [ "$out" = "keel 0.1.0" ]; check "version" $?
k validate; [ $rc -eq 0 ] && has 'is valid (2 sensors, keel 0.1.0 pinned)'; check "imported layout validates" $?
grep -q '^    adapter: guard$' "$r/.agents/keel.yaml" && grep -q '^    exec: scripts/sensors/lint.sh$' "$r/.agents/keel.yaml"; check "import: guard becomes the native adapter, lint stays exec" $?
k import; [ $rc -eq 3 ] && has 'pass --force'; check "import refuses to overwrite keel.yaml" $?

# validation: every problem is exit 3, never a pass
for c in 's/^version: 1$/version: 2/|version must be 1' \
         's/^requires: .*/requires: ">=0.1,<0.2"/|exact version' \
         's/^gate:$/bogus: 1\ngate:/|field bogus not found' \
         's#exec: scripts/sensors/lint.sh#exec: scripts/sensors/nope.sh#|does not exist' \
         's#exec: scripts/sensors/lint.sh#exec: ../lint.sh#|clean path inside the repository' \
         's#    adapter: guard#    adapter: guard\n    exec: scripts/sensors/guard.sh#|exactly one of exec and adapter' \
         's#adapter: guard#adapter: nope#|unknown adapter' \
         's#  - id: lint#  - id: other#|id must equal the exec file name' \
         's#  - id: lint#  - id: guard#|duplicate id' \
         's#gate: fast#gate: medium#|gate must be fast or slow'; do
  mk; yaml_set "${c%%|*}"; k gate fast; [ $rc -eq 3 ] && has "${c#*|}"; check "invalid keel.yaml -> exit 3: ${c#*|}" $?
done
mk; printf '#!/usr/bin/env bash\nexit 0\n' > "$r/scripts/sensors/extra.sh"; k gate fast
[ $rc -eq 3 ] && has 'scripts/sensors/extra.sh is not listed under sensors:'; check "an unlisted sensor file fails validation" $?
mk; mkdir -p "$r/scripts/sensors/disabled"; : > "$r/scripts/sensors/_util.sh"; : > "$r/scripts/sensors/disabled/x.sh"; k validate
[ $rc -eq 0 ]; check "_files and disabled/ are not unlisted sensors" $?

# the pin: keel.yaml, keel.lock and the running binary must agree
mk; yaml_set 's/^requires: .*/requires: 9.9.9/'; k gate fast
[ $rc -eq 3 ] && has 'requires keel 9.9.9, but this is keel 0.1.0'; check "pin: other version -> exit 3" $?
mk; rm "$r/.agents/keel.lock"; k gate fast; [ $rc -eq 3 ] && has 'no .agents/keel.lock'; check "pin: missing lock -> exit 3" $?
mk; sed -i 's/^version\t.*/version\t0.0.9/' "$r/.agents/keel.lock"; k gate fast; [ $rc -eq 3 ] && has 'pins keel 0.0.9'; check "pin: lock version differs -> exit 3" $?
mk; sed -i -E 's/\t[0-9a-f]{64}$/\t0000000000000000000000000000000000000000000000000000000000000000/' "$r/.agents/keel.lock"; k gate fast
[ $rc -eq 3 ] && has 'is not the build .agents/keel.lock pins'; check "pin: binary checksum differs -> exit 3" $?

# commands
mk; mkdir -p "$r/src/deep"; out="$(cd "$r/src/deep" && "$BIN" gate fast 2>&1)"; rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | grep -q '^gate: fast - PASSED (2 of 2)'; check "gate finds the root from a subdirectory" $?
mk; k gate bogus; [ $rc -eq 64 ]; check "gate bogus -> 64" $?
mk; k gate --sensor nope; [ $rc -eq 64 ] && has 'no sensor "nope"'; check "gate --sensor unknown -> 64" $?
mk; out="$(cd "$r" && SCOPE=$'a.ts\nb.ts' "$BIN" gate --sensor lint 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ "$(printf '%s\n' "$out" | head -1)" = "$(printf 'lint\theuristic\tpass\tok')" ] && [ "$(cat "$r/scope.out")" = $'a.ts\nb.ts' ]
check "gate --sensor prints the raw contract output and passes SCOPE through" $?
mk; k measure lint; [ $rc -eq 0 ] && has 'measured'; check "measure sets KEEL_MEASURE=1" $?
mk; k guard; [ $rc -eq 0 ] && [ "$(printf '%s\n' "$out" | head -1 | cut -f1-3)" = "$(printf 'guard\tsecurity\tpass')" ]; check "guard on a clean harness passes" $?

# guard over keel.yaml: the loosenings an engine switch could otherwise hide
mk; yaml_set '/  - id: guard/,/adapter: guard/d'; k gate fast
[ $rc -eq 3 ] && has 'must list the guard sensor'; check "an installed harness cannot drop the guard entry (exit 3)" $?
mk; rm "$r/.agents/state.yml"; yaml_set '/  - id: guard/,/adapter: guard/d'; k validate
[ $rc -eq 0 ]; check "without .agents/state.yml the guard entry is optional" $?
mk; (cd "$r" && rm -f .agents/keel.yaml && "$BIN" import >/dev/null); grep -q '^    adapter: guard$' "$r/.agents/keel.yaml"
check "import adds the guard adapter to an installed harness that lacks guard.sh" $?
mk; mkdir -p "$r/scripts/sensors/disabled"; (cd "$r" && git mv scripts/sensors/lint.sh scripts/sensors/disabled/lint.sh); yaml_set '/  - id: lint/,/exec: /d'; k guard
[ $rc -eq 1 ] && has 'scripts/sensors/lint.sh: sensor removed or disabled'; check "guard: an exec entry dropped with its file names the file" $?
mk; yaml_set '0,/ceiling_seconds: 30/s//ceiling_seconds: 90/'; k guard
[ $rc -eq 1 ] && has '.agents/keel.yaml: gate.fast.ceiling_seconds raised from 30 to 90'; check "guard: a raised keel.yaml budget is a loosening" $?
printf '# ADR 0009\nThe fast gate needs 90s: `.agents/keel.yaml`.\n' > "$r/docs/adr/0009-budget.md"; k guard
[ $rc -eq 0 ] && has '1 loosening(s)'; check "guard: an added ADR naming .agents/keel.yaml covers it" $?

# engine switch: budgets move from gate.env at the base to keel.yaml now
r="$(new_repo)"; mkdir -p "$r/scripts/sensors" "$r/.agents"; printf 'schema_version: 2\n' > "$r/.agents/state.yml"
cp "$KEEL/skills/build/assets/gate.env" "$r/.agents/gate.env"; cp "$KEEL/skills/build/assets/sensors/common/guard.sh" "$r/scripts/sensors/guard.sh"
(cd "$r" && git add -A && git commit -qm bash-engine && "$BIN" import --sums "$SUMS" >/dev/null && git rm -q .agents/gate.env)
k guard; [ $rc -eq 0 ]; check "engine switch with the same budgets passes" $?
yaml_set '0,/ceiling_seconds: 30/s//ceiling_seconds: 300/'; k guard
[ $rc -eq 1 ] && has 'gate.fast.ceiling_seconds raised from 30 to 300'; check "engine switch cannot raise a budget" $?
finish
````

File `tests/keel_cli_parity_test.sh`:

````bash
#!/usr/bin/env bash
# Parity: on the same repository, `bash scripts/gate.sh` and `keel gate` print the same report,
# write the same log and exit with the same code. Only the timing columns are normalised.
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
BIN="${KEEL_BIN:-$(cd "$(dirname "$0")/.." && pwd)/cli/keel/dist/keel}"
SUMS="$(dirname "$BIN")/SHA256SUMS"
if [ ! -x "$BIN" ]; then
  if [ -n "${CI:-}" ]; then fail "keel CLI not built (make -C cli/keel build is required in CI)"; finish; fi
  echo "  skip keel CLI parity: $BIN not built (make -C cli/keel build)"; exit 0
fi

# mk -> repo with the real gate.sh and gate.env (installed by copy, whatever KEEL_ENGINE says)
mk() {
  local r; r="$(new_repo "$@")"
  mkdir -p "$r/scripts/sensors" "$r/.agents"
  cp "$KEEL/skills/build/assets/gate.sh" "$r/scripts/gate.sh"
  cp "$KEEL/skills/build/assets/gate.env" "$r/.agents/gate.env"
  printf '%s\n' "$r"
}
# sensor REPO RELPATH SCRIPT-BODY
sensor() { mkdir -p "$(dirname "$1/$2")"; printf '#!/usr/bin/env bash\n%s\n' "$3" > "$1/$2"; }
# norm: drop the per-sensor time column and the spent value; everything else must match byte for byte
norm() { sed -E 's/ +[0-9]+(\.[0-9])?m?s$/ <t>/; s/spent [0-9]+(\.[0-9])?m?s/spent <t>/'; }
# same NAME REPO [MODE]: import keel.yaml from the layout, commit it, run both engines, compare
same() {
  local name="$1" r="$2" mode="${3:-fast}" b c rb rc lb lc
  (cd "$r" && "$BIN" import --force --sums "$SUMS" >/dev/null && git add .agents/keel.yaml .agents/keel.lock >/dev/null 2>&1 &&
    { git rev-parse -q --verify HEAD >/dev/null && git commit -qm keel >/dev/null || true; })
  b="$(cd "$r" && LC_ALL=C bash scripts/gate.sh "$mode" 2>&1)"; rb=$?
  lb="$(norm < "$r/$(log_of "$mode")")"
  c="$(cd "$r" && LC_ALL=C "$BIN" gate "$mode" 2>&1)"; rc=$?
  lc="$(norm < "$r/$(log_of "$mode")")"
  [ "$rb" = "$rc" ] && [ "$(printf '%s\n' "$b" | norm)" = "$(printf '%s\n' "$c" | norm)" ] && [ "$lb" = "$lc" ]
  check "parity: $name (rc $rb)" $?
  if [ "$rb" != "$rc" ] || [ "$(printf '%s\n' "$b" | norm)" != "$(printf '%s\n' "$c" | norm)" ]; then
    diff <(printf '%s\n' "$b" | norm) <(printf '%s\n' "$c" | norm) | head -10 | sed 's/^/    /'
  fi
}
log_of() { if [ "$1" = slow ]; then echo .agents/last-run-slow.log; else echo .agents/last-run.log; fi; }

r="$(mk)"
sensor "$r" scripts/sensors/a.sh "printf 'a\tcorrectness\tpass\tok a\n'"
sensor "$r" scripts/sensors/b.sh "printf 'b\theuristic\tfail\t2 file(s) above baseline\n  src/x.ts: 3 problems (allowed 1)\n  guidance: fix it\n'; exit 1"
sensor "$r" scripts/sensors/c.sh "printf 'c\tcorrectness\tskip\ttool missing - run: make bootstrap\n'; exit 2"
same "pass, fail with details and guidance, skip" "$r"

r="$(mk)"
sensor "$r" scripts/sensors/acentuação-longa-demais.sh "printf 'acentuação-longa-demais\theuristic\tpass\tCódigo em português: 0 arquivos fora do padrão, nenhum acima do baseline\n'"
sensor "$r" scripts/sensors/ação.sh "printf 'ação\tcorrectness\tpass\tnão\n'"
sensor "$r" scripts/sensors/notabs.sh "echo 'no tabs on this line'"
sensor "$r" scripts/sensors/quiet.sh "exit 0"
sensor "$r" scripts/sensors/stderr.sh "printf 'stderr\tcorrectness\tfail\tmixed\n'; echo '  to stderr' >&2; echo '  to stdout'; printf '\n\n'; exit 3"
same "non-ASCII and long fields (byte padding), no TAB, empty output, stderr, rc 3" "$r"

r="$(mk)"
sensor "$r" scripts/sensors/a.sh "printf 'a\tcorrectness\tpass\tok\n'"
sensor "$r" scripts/sensors/_util.sh "exit 1"
sensor "$r" scripts/sensors/disabled/x.sh "exit 1"
sensor "$r" scripts/sensors/slow/s.sh "printf 's\tcorrectness\tpass\tslow one\n'"
sensor "$r" scripts/sensors/architecture.sh "printf 'architecture\tcorrectness\tpass\tok\n'"
sensor "$r" scripts/sensors/architecture-grep.sh "printf 'architecture-grep\tcorrectness\tpass\tok\n'"
same "discovery order and ignored files (fast)" "$r"
same "slow gate" "$r" slow

r="$(mk)"
sensor "$r" scripts/sensors/many.sh "printf 'many\tcorrectness\tfail\tmany\n'; for i in \$(seq 1 60); do echo \"  line \$i\"; done; exit 1"
same "truncation at 40 lines" "$r"

r="$(mk)"; printf 'CEILING_SECONDS=1\r\nSLOW_CEILING_SECONDS=600\r\n' > "$r/.agents/gate.env"
sensor "$r" scripts/sensors/slow1.sh "sleep 1.2; printf 'slow1\tcorrectness\tpass\tslow\n'"
same "over ceiling, CRLF gate.env" "$r"

r="$(mk)"
sensor "$r" scripts/sensors/scope.sh "printf 'scope\tcorrectness\tpass\t%s\n' \"\$(printf '%s' \"\$SCOPE\" | tr '\n' ',')\""
(cd "$r" && git add -A && git commit -qm base); echo 2 > "$r/my file ação.ts"; echo 1 > "$r/b.ts"; mkdir -p "$r/.agents/.gate-lock"
same "SCOPE: untracked, spaces, non-ASCII, run state excluded" "$r"

r="$(mk --no-commit)"
sensor "$r" scripts/sensors/a.sh "printf 'a\tcorrectness\tpass\tok\n'"
same "no commits yet" "$r"

r="$(mk)"
same "no sensors" "$r"
finish
````

  Make both bash tests executable: `chmod +x tests/keel_cli_test.sh tests/keel_cli_parity_test.sh`.
- [ ] **Step 2: run them.**
  - `cd cli/keel && go test ./internal/gate/ ./internal/importer/` → `FAIL` (`undefined: cutField`, `undefined: Render`).
  - `CI=1 bash tests/keel_cli_test.sh; echo rc=$?` → `  FAIL keel CLI not built (make -C cli/keel build is required in CI)` and `rc=1`.
- [ ] **Step 3: create the packages, the command and the build.**

File `cli/keel/internal/gate/gate.go`:

````go
// Package gate runs the fast or the slow gate and renders gate.sh's report byte for byte.
package gate

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/aether-labs-org/plugins/cli/keel/internal/config"
)

// Adapter runs a built-in sensor in-process and returns its contract output and exit code.
type Adapter func(root string) (out string, rc int)

// Adapters maps adapter names to implementations; main wires "guard".
var Adapters = map[string]Adapter{}

var runState = regexp.MustCompile(`^\.agents/(last-[^/]*|\.gate-lock/.*)$`)

func git(root string, args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = root
	out, err := cmd.Output()
	return string(out), err
}

// Scope returns gate.sh's SCOPE (changed files since HEAD, untracked included, deleted and keel's run
// state excluded, sorted bytewise and unique) and the note used when it is empty.
func Scope(root string) (scope, emptyNote string) {
	if _, err := git(root, "rev-parse", "--verify", "-q", "HEAD"); err != nil {
		return "", "no commits yet"
	}
	diff, _ := git(root, "-c", "core.quotepath=off", "diff", "--name-only", "--diff-filter=d", "HEAD")
	others, _ := git(root, "-c", "core.quotepath=off", "ls-files", "--others", "--exclude-standard")
	set := map[string]bool{}
	for _, l := range strings.Split(diff+"\n"+others, "\n") {
		if l != "" && !runState.MatchString(l) {
			set[l] = true
		}
	}
	files := make([]string, 0, len(set))
	for f := range set {
		files = append(files, f)
	}
	sort.Strings(files)
	return strings.Join(files, "\n"), "no uncommitted changes"
}

// RunSensor runs one sensor from root with SCOPE (and the rest of env) as given, the way gate.sh
// did: `bash <file>` with stderr merged into stdout. It returns the raw output and the exit code.
func RunSensor(root string, s config.Sensor, env []string) (string, int) {
	if s.Adapter != "" {
		a, ok := Adapters[s.Adapter]
		if !ok {
			return "", 127
		}
		return a(root)
	}
	cmd := exec.Command("bash", s.Exec)
	cmd.Dir = root
	cmd.Env = env
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	err := cmd.Run()
	rc := 0
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			rc = ee.ExitCode()
		} else {
			rc = 127
		}
	}
	return buf.String(), rc
}

// WithScope returns env with SCOPE replaced.
func WithScope(env []string, scope string) []string {
	out := make([]string, 0, len(env)+1)
	for _, kv := range env {
		if !strings.HasPrefix(kv, "SCOPE=") {
			out = append(out, kv)
		}
	}
	return append(out, "SCOPE="+scope)
}

// cutField mimics `cut -f n` on one line: a line without a TAB is printed whole.
func cutField(line string, n int) string {
	if !strings.Contains(line, "\t") {
		return line
	}
	f := strings.Split(line, "\t")
	if n-1 < len(f) {
		return f[n-1]
	}
	return ""
}

// padRight and padLeft pad by bytes, as bash's printf %-Ns and %Ns do in every locale.
func padRight(s string, w int) string {
	if len(s) >= w {
		return s
	}
	return s + strings.Repeat(" ", w-len(s))
}

func padLeft(s string, w int) string {
	if len(s) >= w {
		return s
	}
	return strings.Repeat(" ", w-len(s)) + s
}

func duration(ms int64) string {
	if ms >= 1000 {
		return fmt.Sprintf("%d.%ds", ms/1000, (ms%1000)/100)
	}
	return fmt.Sprintf("%dms", ms)
}

// Marks returns pass/fail/skip marks: Unicode only on a UTF-8 terminal, like gate.sh.
func Marks(tty bool) (string, string, string) {
	if tty && utf8Locale() {
		return "✓", "✗", "○"
	}
	return "v", "x", "-"
}

func utf8Locale() bool {
	for _, k := range []string{"LC_ALL", "LC_CTYPE", "LANG"} {
		if v := os.Getenv(k); v != "" {
			v = strings.ToLower(v)
			return strings.Contains(v, "utf-8") || strings.Contains(v, "utf8")
		}
	}
	return false
}

// IsTTY reports whether f is a terminal.
func IsTTY(f *os.File) bool {
	st, err := f.Stat()
	return err == nil && st.Mode()&os.ModeCharDevice != 0
}

// LogPath is where the full report of a gate run is kept.
func LogPath(mode string) string {
	if mode == "slow" {
		return ".agents/last-run-slow.log"
	}
	return ".agents/last-run.log"
}

// Run runs every sensor of the gate, writes the full report to LogPath(mode), prints at most 40
// lines of it to w plus where the full log is, and returns 1 when any sensor failed, else 0.
func Run(root, mode string, c *config.Config, w io.Writer, tty bool) int {
	_ = os.MkdirAll(filepath.Join(root, ".agents"), 0o755)
	mPass, mFail, mSkip := Marks(tty)
	scope, emptyNote := Scope(root)
	env := WithScope(os.Environ(), scope)
	nScope := 0
	for _, l := range strings.Split(scope, "\n") {
		if l != "" {
			nScope++
		}
	}

	var report strings.Builder
	var totalMS int64
	n, failed, skipped := 0, 0, 0
	for _, s := range c.SensorsFor(mode) {
		n++
		start := time.Now()
		raw, rc := RunSensor(root, s, env)
		ms := time.Since(start).Milliseconds()
		totalMS += ms

		out := strings.TrimRight(raw, "\n") // $(...) strips trailing newlines
		head1, rest, _ := strings.Cut(out, "\n")
		body := strings.TrimRight(rest, "\n")
		cls, sum := cutField(head1, 2), cutField(head1, 4)

		mark := mPass
		switch rc {
		case 0:
		case 2:
			mark = mSkip
			skipped++
		default:
			mark = mFail
			failed++
		}
		fmt.Fprintf(&report, "%s %s [%s] %s %s\n", mark, padRight(s.ID, 12), padRight(cls, 11), padRight(sum, 44), padLeft(duration(ms), 8))
		if body != "" {
			report.WriteString(body + "\n")
		}
	}

	scopeLine := "scope: whole repository (" + emptyNote + ")"
	if nScope > 0 {
		scopeLine = fmt.Sprintf("scope: %d files changed since last commit", nScope)
	}
	ceiling := c.Ceiling(mode)
	over := ""
	if totalMS > int64(ceiling)*1000 {
		over = " (over ceiling)"
	}
	ran := n - skipped
	var verdict string
	switch {
	case skipped == 0 && failed > 0:
		verdict = fmt.Sprintf("FAILED (%d of %d)", failed, n)
	case skipped == 0:
		verdict = fmt.Sprintf("PASSED (%d of %d)", n, n)
	case failed > 0:
		verdict = fmt.Sprintf("FAILED (%d of %d, %d skipped)", failed, ran, skipped)
	default:
		verdict = fmt.Sprintf("PASSED (%d of %d, %d skipped)", ran-failed, ran, skipped)
	}
	full := report.String() + "\n" + scopeLine + "\n" +
		fmt.Sprintf("gate: %s - %s | ceiling %ds, spent %s%s | model cost: US$0.00\n", mode, verdict, ceiling, duration(totalMS), over)

	log := LogPath(mode)
	_ = os.WriteFile(filepath.Join(root, log), []byte(full), 0o644)
	lines := strings.SplitAfter(full, "\n")
	if lines[len(lines)-1] == "" {
		lines = lines[:len(lines)-1]
	}
	if len(lines) > 40 {
		io.WriteString(w, strings.Join(lines[:40], ""))
		fmt.Fprintf(w, "output truncated at 40 lines - full log in %s\n", log)
	} else {
		io.WriteString(w, full)
		fmt.Fprintf(w, "full log in %s\n", log)
	}
	if failed > 0 {
		return 1
	}
	return 0
}
````

File `cli/keel/internal/importer/importer.go`:

````go
// Package importer writes .agents/keel.yaml (and .agents/keel.lock) from a bash-engine install:
// the sensors gate.sh would run, in its order, and the budgets of .agents/gate.env.
package importer

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/aether-labs-org/plugins/cli/keel/internal/config"
)

// Native maps a bash sensor file name to the built-in adapter that replaces it in this version.
var Native = map[string]string{"guard": "guard"}

// ceiling reads KEY like gate.sh: CR removed, first `^KEY=<digits>` line, else def.
func ceiling(root, key string, def int) int {
	b, err := os.ReadFile(filepath.Join(root, ".agents/gate.env"))
	if err != nil {
		return def
	}
	re := regexp.MustCompile(`^` + key + `=([0-9]+)`)
	for _, l := range strings.Split(strings.ReplaceAll(string(b), "\r", ""), "\n") {
		if m := re.FindStringSubmatch(l); m != nil {
			if n, err := strconv.Atoi(m[1]); err == nil {
				return n
			}
		}
	}
	return def
}

// discover lists the sensors gate.sh would run from dir: top-level *.sh files not starting with `_`.
func discover(root, dir, gate string) []config.Sensor {
	files, _ := filepath.Glob(filepath.Join(root, dir, "*.sh"))
	sort.Strings(files)
	var out []config.Sensor
	for _, f := range files {
		id := strings.TrimSuffix(filepath.Base(f), ".sh")
		if strings.HasPrefix(id, "_") {
			continue
		}
		if st, err := os.Stat(f); err != nil || !st.Mode().IsRegular() {
			continue
		}
		s := config.Sensor{ID: id, Gate: gate, Exec: dir + "/" + id + ".sh"}
		if a, ok := Native[id]; ok && gate == "fast" {
			s.Exec, s.Adapter = "", a
		}
		out = append(out, s)
	}
	return out
}

// Render writes c in keel's canonical layout, so a diff of keel.yaml stays readable.
func Render(c *config.Config) string {
	var b strings.Builder
	b.WriteString("# Managed by keel. The sensors and budgets of this repository's gates; check with `keel validate`.\n")
	fmt.Fprintf(&b, "version: %d\nrequires: %s\ngate:\n  fast:\n    ceiling_seconds: %d\n  slow:\n    ceiling_seconds: %d\n",
		c.Version, c.Requires, c.Ceiling("fast"), c.Ceiling("slow"))
	if len(c.Sensors) == 0 {
		b.WriteString("sensors: []\n")
		return b.String()
	}
	b.WriteString("sensors:\n")
	for _, s := range c.Sensors {
		fmt.Fprintf(&b, "  - id: %s\n    gate: %s\n", s.ID, s.Gate)
		if s.Adapter != "" {
			fmt.Fprintf(&b, "    adapter: %s\n", s.Adapter)
		} else {
			fmt.Fprintf(&b, "    exec: %s\n", s.Exec)
		}
	}
	return b.String()
}

// ReadSums parses `sha256sum` output whose names are `<os>-<arch>/keel` (as in engine/SHA256SUMS).
func ReadSums(path string) (map[string]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	sums := map[string]string{}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) != 2 {
			continue
		}
		name := strings.TrimPrefix(fields[1], "*")
		if plat, ok := strings.CutSuffix(name, "/keel"); ok {
			sums[plat] = fields[0]
		}
	}
	if len(sums) == 0 {
		return nil, fmt.Errorf("%s has no <os>-<arch>/keel rows", path)
	}
	return sums, sc.Err()
}

// RenderLock writes the lock file for version with the given checksums, platforms sorted.
func RenderLock(version string, sums map[string]string) string {
	var b strings.Builder
	b.WriteString("# Managed by keel. The pinned keel build; written by keel import --sums or /keel-harness:build, never by hand.\n")
	fmt.Fprintf(&b, "version\t%s\n", version)
	plats := make([]string, 0, len(sums))
	for p := range sums {
		plats = append(plats, p)
	}
	sort.Strings(plats)
	for _, p := range plats {
		fmt.Fprintf(&b, "%s\t%s\n", p, sums[p])
	}
	return b.String()
}

// Import builds the config of a bash-engine install under root for keel version.
func Import(root, version string) *config.Config {
	c := &config.Config{Version: 1, Requires: version}
	c.Gate.Fast.CeilingSeconds = ceiling(root, "CEILING_SECONDS", config.DefaultFastCeiling)
	c.Gate.Slow.CeilingSeconds = ceiling(root, "SLOW_CEILING_SECONDS", config.DefaultSlowCeiling)
	c.Sensors = append(discover(root, "scripts/sensors", "fast"), discover(root, "scripts/sensors/slow", "slow")...)
	if _, err := os.Stat(filepath.Join(root, ".agents/state.yml")); err == nil {
		if _, ok := c.Find("guard"); !ok {
			c.Sensors = append([]config.Sensor{{ID: "guard", Gate: "fast", Adapter: "guard"}}, c.Sensors...)
			sort.SliceStable(c.Sensors, func(i, j int) bool {
				return c.Sensors[i].Gate == "fast" && c.Sensors[j].Gate == "slow" ||
					c.Sensors[i].Gate == c.Sensors[j].Gate && c.Sensors[i].ID+".sh" < c.Sensors[j].ID+".sh"
			})
		}
	}
	return c
}
````

File `cli/keel/main.go`:

````go
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
````

File `cli/keel/Makefile`:

````make
# keel CLI. `make build` -> dist/keel + dist/SHA256SUMS for this machine; `make dist` -> every platform.
VERSION   := 0.1.0
export GOTOOLCHAIN := go1.27.3
PLATFORMS := linux-amd64 linux-arm64 darwin-amd64 darwin-arm64
GOFLAGS   := -trimpath -buildvcs=false
LDFLAGS   := -s -w -buildid= -X main.version=$(VERSION)
HOST      := $(shell go env GOOS)-$(shell go env GOARCH)

.PHONY: build dist test
build:
	CGO_ENABLED=0 go build $(GOFLAGS) -ldflags '$(LDFLAGS)' -o dist/keel .
	mkdir -p dist/$(HOST) && cp dist/keel dist/$(HOST)/keel
	cd dist && sha256sum $(HOST)/keel > SHA256SUMS

dist:
	rm -rf dist/engine && mkdir -p dist/engine
	for p in $(PLATFORMS); do \
	  CGO_ENABLED=0 GOOS=$${p%-*} GOARCH=$${p#*-} go build $(GOFLAGS) -ldflags '$(LDFLAGS)' -o dist/engine/$$p/keel . || exit 1; \
	done
	cd dist/engine && sha256sum */keel > SHA256SUMS

test:
	go vet ./...
	go test ./...
````

  The `Makefile` recipes are indented with a TAB.

File `cli/keel/README.md`:

````markdown
# keel CLI

`keel` runs a repository's keel gates from `.agents/keel.yaml` and keeps the sensor contract of
`plugins/keel-harness/skills/build/references/sensor-contract.md` byte for byte. Design:
`docs/specs/2026-10-24-keel-cli-design.md`; plan: `docs/plans/2026-10-24-keel-cli-plan.md`.

Not wired into the plugin until phase F4: installed repositories still run the bash engine.

| Command | Does | Exit |
| --- | --- | --- |
| `keel gate [fast\|slow]` | runs a gate; report and `.agents/last-run*.log` as `scripts/gate.sh` | 0 pass, 1 fail |
| `keel gate --sensor <id>` | runs one sensor with `SCOPE` as given; prints its contract output | the sensor's 0/1/2 |
| `keel measure <id>` | the same with `KEEL_MEASURE=1` | the sensor's |
| `keel guard` | the native guard sensor (D32, extended to keel.yaml) | 0/1 |
| `keel validate` | keel.yaml, keel.lock and the pin | 0, or 3 |
| `keel import [--force] [--sums FILE]` | keel.yaml (and keel.lock) from a bash-engine install | 0, or 3 |

Every configuration or pin problem exits 3 and is never a pass; bad usage exits 64.

    make build   # dist/keel and dist/SHA256SUMS for this machine
    make dist    # dist/engine/<os>-<arch>/keel and SHA256SUMS, byte-reproducible
    make test    # go vet + go test
    make -C ../.. check-cli   # unit tests, then the whole suite on the bash and the CLI engine
````

- [ ] **Step 4: run them.**
  - `make -C cli/keel test build` → `go vet` silent, `ok` for the five packages, and `dist/keel`; `cli/keel/dist/keel version` → `keel 0.1.0`.
  - `CI=1 bash tests/keel_cli_test.sh; echo rc=$?` → 34 `ok`, `rc=0`.
  - `CI=1 bash tests/keel_cli_parity_test.sh; echo rc=$?` → 9 `ok` (`parity: …`), `rc=0`.
  - `./tests/run.sh; echo rc=$?` → `rc=0` with **N + 43** `ok`.
  - `git status --short cli/keel/dist` → no output (ignored).
- [ ] **Step 5: commit and push.** `feat(keel-cli): keel gate runs exec sensors with gate.sh's report byte for byte`

---

## Task 4 — the existing suite runs on the CLI engine (`KEEL_ENGINE=cli`)

**Files:** create `tests/keel_run_sensor.sh`; modify `tests/keel_helpers.sh`, `tests/keel_ts_sensors_test.sh`,
`tests/keel_python_sensors_test.sh`, `tests/keel_jvm_sensors_test.sh`, `tests/keel_rule_sensors_test.sh`,
`tests/keel_guard_test.sh`, `tests/keel_envparse_test.sh`.

**Interfaces — produces:** `KEEL_ENGINE` (`bash` default | `cli`), `RUN_SENSOR` (path of `tests/keel_run_sensor.sh`), `KEEL_BIN`, `KEEL_SUMS`,
`bash_only DESC CMD...`. Under `cli`: `install_asset … build/assets/gate.sh …` installs a test shim that runs `keel import --force --sums` and then
`keel gate "$@"`; `bash "$RUN_SENSOR" scripts/sensors/<id>.sh` runs `keel gate --sensor <id>` on a freshly imported `keel.yaml`. The wrappers stay
the files the tests edit (`sed -i` on a repo-specific block still works), so this is the exec adapter under test, not a copy of it.

- [ ] **Step 1: see that the engine is ignored today.** `KEEL_ENGINE=cli KEEL_BIN=/bin/false bash tests/keel_gate_test.sh | grep -c FAIL` → `0`.
- [ ] **Step 2: the runner.**

File `tests/keel_run_sensor.sh`:

````bash
#!/usr/bin/env bash
# keel_run_sensor.sh FILE -> runs one sensor from the repository root the way the selected engine
# does: `bash FILE` (KEEL_ENGINE=bash), or `keel gate --sensor <id>` on a keel.yaml imported from
# the same layout (KEEL_ENGINE=cli). SCOPE, KEEL_MEASURE and the rest of the environment pass through.
if [ "${KEEL_ENGINE:-bash}" = cli ]; then
  "$KEEL_BIN" import --force --sums "$KEEL_SUMS" >/dev/null || exit 3
  exec "$KEEL_BIN" gate --sensor "$(basename "$1" .sh)"
fi
exec bash "$1"
````

  `chmod +x tests/keel_run_sensor.sh`.
- [ ] **Step 3: the helpers and the seven tests.** Every direct `bash scripts/sensors/…` becomes `bash "$RUN_SENSOR" scripts/sensors/…`; in `keel_guard_test.sh`, the budget message accepts both keys and the `envparse.sh` dependency becomes `bash_only`.

Patch:

````diff
diff --git a/tests/keel_envparse_test.sh b/tests/keel_envparse_test.sh
index 132e875..606a6ef 100755
--- a/tests/keel_envparse_test.sh
+++ b/tests/keel_envparse_test.sh
@@ -56,12 +56,12 @@ install_asset "$r" build/assets/lib/envparse.sh scripts/lib/envparse.sh
 install_asset "$r" rules/assets/sensors/file-size.sh scripts/sensors/file-size.sh
 mkdir -p "$r/.agents/rules" "$r/src"
 printf 'LIMIT=$(touch PWNED)\nINCLUDE=src\n' > "$r/.agents/rules/file-size.env"
-out="$(cd "$r" && bash scripts/sensors/file-size.sh)"; rc=$?
+out="$(cd "$r" && bash "$RUN_SENSOR" scripts/sensors/file-size.sh)"; rc=$?
 [ $rc -eq 1 ] && [ "$(printf '%s\n' "$out" | head -1 | cut -f1,3)" = "file-size	fail" ] && [ ! -e "$r/PWNED" ]
 check "sensor: hostile env -> fail line 1, nothing executed" $?
 printf '%s\n' "$out" | grep -q '^  guidance: '; check "sensor: hostile env -> guidance" $?
 rm "$r/scripts/lib/envparse.sh"; printf 'LIMIT=10\nINCLUDE=src\n' > "$r/.agents/rules/file-size.env"
-out="$(cd "$r" && bash scripts/sensors/file-size.sh)"; rc=$?
+out="$(cd "$r" && bash "$RUN_SENSOR" scripts/sensors/file-size.sh)"; rc=$?
 [ $rc -eq 2 ] && printf '%s' "$out" | head -1 | grep -q 'envparse.sh is missing'; check "sensor: missing lib -> skip naming it" $?
 
 finish
diff --git a/tests/keel_guard_test.sh b/tests/keel_guard_test.sh
index a0043b6..b5d533c 100755
--- a/tests/keel_guard_test.sh
+++ b/tests/keel_guard_test.sh
@@ -20,7 +20,7 @@ mk() {
   (cd "$r" && git add -A && git commit -q -m harness)
   printf '%s\n' "$r"
 }
-run() { out="$(cd "$1" && bash scripts/sensors/guard.sh)"; rc=$?; }
+run() { out="$(cd "$1" && bash "$RUN_SENSOR" scripts/sensors/guard.sh)"; rc=$?; }
 head1() { printf '%s\n' "$out" | head -1 | cut -f1-3; }
 
 r="$(mk)"; run "$r"
@@ -63,7 +63,8 @@ run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | grep -qF 'ENFORCEMENT changed';
 r="$(mk)"; rm "$r/.agents/rules/file-size.env"
 run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | grep -qF 'rule deleted'; check "deleting a rule fails" $?
 r="$(mk)"; sed -i.bak 's/CEILING_SECONDS=30/CEILING_SECONDS=300/' "$r/.agents/gate.env"; rm -f "$r/.agents/gate.env.bak"
-run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | grep -qF 'CEILING_SECONDS raised from 30 to 300'; check "raising the fast budget fails" $?
+# The CLI engine keeps the budgets in .agents/keel.yaml and names the key in that file's terms.
+run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | grep -qE '(CEILING_SECONDS|gate\.fast\.ceiling_seconds) raised from 30 to 300'; check "raising the fast budget fails" $?
 r="$(mk)"; mkdir -p "$r/scripts/sensors/disabled"; (cd "$r" && git mv scripts/sensors/file-size.sh scripts/sensors/disabled/file-size.sh)
 run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | grep -qF 'scripts/sensors/file-size.sh: sensor removed or disabled'; check "disabling a sensor fails" $?
 
@@ -71,8 +72,8 @@ run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | grep -qF 'scripts/sensors/file-s
 r="$(mk)"; (cd "$r" && git update-ref refs/remotes/origin/main HEAD && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main)
 sed -i.bak 's/LIMIT=10/LIMIT=99/' "$r/.agents/rules/file-size.env"; rm -f "$r/.agents/rules/file-size.env.bak"; (cd "$r" && git commit -qam loosen)
 run "$r"; [ $rc -eq 1 ]; check "a committed loosening fails against the merge-base with origin/HEAD" $?
-out="$(cd "$r" && KEEL_GUARD_BASE=HEAD bash scripts/sensors/guard.sh)"; [ $? -eq 0 ]; check "KEEL_GUARD_BASE overrides the base" $?
-out="$(cd "$r" && KEEL_GUARD_BASE=nope bash scripts/sensors/guard.sh)"; [ $? -eq 1 ] && printf '%s' "$out" | grep -q 'is not a commit'; check "a bad KEEL_GUARD_BASE fails" $?
+out="$(cd "$r" && KEEL_GUARD_BASE=HEAD bash "$RUN_SENSOR" scripts/sensors/guard.sh)"; [ $? -eq 0 ]; check "KEEL_GUARD_BASE overrides the base" $?
+out="$(cd "$r" && KEEL_GUARD_BASE=nope bash "$RUN_SENSOR" scripts/sensors/guard.sh)"; [ $? -eq 1 ] && printf '%s' "$out" | grep -q 'is not a commit'; check "a bad KEEL_GUARD_BASE fails" $?
 
 # install and edge cases
 r="$(new_repo --no-commit)"; install_asset "$r" build/assets/lib/envparse.sh scripts/lib/envparse.sh; install_asset "$r" build/assets/sensors/common/guard.sh scripts/sensors/guard.sh
@@ -80,5 +81,5 @@ run "$r"; [ $rc -eq 0 ] && printf '%s' "$out" | grep -q 'No commits yet'; check
 r="$(new_repo)"; install_asset "$r" build/assets/lib/envparse.sh scripts/lib/envparse.sh; install_asset "$r" build/assets/sensors/common/guard.sh scripts/sensors/guard.sh
 mkdir -p "$r/.agents/baselines"; printf 'schema_version: 2\n' > "$r/.agents/state.yml"; printf 'src/a.ts\t9\n' > "$r/.agents/baselines/lint.tsv"
 run "$r"; [ $rc -eq 0 ] && printf '%s' "$out" | grep -q 'Harness installed in this change'; check "harness installed in this change: pass" $?
-r="$(mk)"; rm "$r/scripts/lib/envparse.sh"; run "$r"; [ $rc -eq 2 ]; check "missing envparse lib: skip" $?
+r="$(mk)"; rm "$r/scripts/lib/envparse.sh"; run "$r"; bash_only "missing envparse lib: skip" [ $rc -eq 2 ]
 finish
diff --git a/tests/keel_helpers.sh b/tests/keel_helpers.sh
index 144acc8..e5feadb 100644
--- a/tests/keel_helpers.sh
+++ b/tests/keel_helpers.sh
@@ -4,6 +4,16 @@ KEEL="$(cd "$(dirname "${BASH_SOURCE[0]}")/../plugins/keel-harness" && pwd)"
 STUBS="$(cd "$(dirname "${BASH_SOURCE[0]}")/fixtures/keel/stubs" && pwd)"
 FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/fixtures/keel" && pwd)"
 export KEEL STUBS FIXTURES
+# KEEL_ENGINE=cli runs every gate and sensor through the keel CLI (cli/keel, built by
+# `make -C cli/keel build`) instead of scripts/gate.sh; the default is the bash engine.
+KEEL_ENGINE="${KEEL_ENGINE:-bash}"
+RUN_SENSOR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/keel_run_sensor.sh"
+export KEEL_ENGINE RUN_SENSOR
+if [ "$KEEL_ENGINE" = cli ]; then
+  KEEL_BIN="${KEEL_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/cli/keel/dist/keel}"
+  KEEL_SUMS="$(dirname "$KEEL_BIN")/SHA256SUMS"
+  export KEEL_BIN KEEL_SUMS
+fi
 _keel_fail=0
 check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; _keel_fail=1; fi; }
 fail() { echo "  FAIL $1"; _keel_fail=1; }
@@ -26,10 +36,23 @@ new_repo() {
   printf '%s\n' "$d"
 }
 # install_asset REPO SRC_REL DEST_REL  (SRC_REL relative to $KEEL/skills/)
+# Under KEEL_ENGINE=cli, gate.sh is replaced by a shim that runs `keel gate` on the same layout.
 install_asset() {
   mkdir -p "$(dirname "$1/$3")"
+  if [ "$KEEL_ENGINE" = cli ] && [ "$2" = build/assets/gate.sh ]; then
+    printf '%s\n' '#!/usr/bin/env bash' 'cd "$(dirname "$0")/.." || exit 1' \
+      '"$KEEL_BIN" import --force --sums "$KEEL_SUMS" >/dev/null || exit 3' 'exec "$KEEL_BIN" gate "$@"' > "$1/$3"
+    chmod +x "$1/$3"; return
+  fi
   cp "$KEEL/skills/$2" "$1/$3" && chmod +x "$1/$3"
 }
+# bash_only DESC CMD... -> runs a check that asserts a bash-engine implementation detail; under
+# KEEL_ENGINE=cli it prints a skip line instead, so the skipped assertions stay countable.
+bash_only() {
+  local d="$1"; shift
+  if [ "$KEEL_ENGINE" = cli ]; then echo "  skip (cli) $d"; return 0; fi
+  "$@"; check "$d" $?
+}
 # use_stub REPO TOOL DEST_REL
 use_stub() {
   mkdir -p "$(dirname "$1/$3")"
diff --git a/tests/keel_jvm_sensors_test.sh b/tests/keel_jvm_sensors_test.sh
index 6a7b656..84f4565 100644
--- a/tests/keel_jvm_sensors_test.sh
+++ b/tests/keel_jvm_sensors_test.sh
@@ -9,7 +9,7 @@ mk() {
   mkdir -p "$r/.agents/baselines" "$r/src/main/kotlin/a" "$r/src/test/kotlin/a"
   printf '%s\n' "$r"
 }
-run() { local r="$1" s="$2"; shift 2; out="$(cd "$r" && env STUB_LOG="$r/stub.log" "$@" bash "scripts/sensors/$s.sh" 2>&1)"; rc=$?; }
+run() { local r="$1" s="$2"; shift 2; out="$(cd "$r" && env STUB_LOG="$r/stub.log" "$@" bash "$RUN_SENSOR" "scripts/sensors/$s.sh" 2>&1)"; rc=$?; }
 
 for s in compile lint tests; do
   f="$KEEL/skills/$SD/$s.sh"
diff --git a/tests/keel_python_sensors_test.sh b/tests/keel_python_sensors_test.sh
index 371143e..25bec25 100644
--- a/tests/keel_python_sensors_test.sh
+++ b/tests/keel_python_sensors_test.sh
@@ -9,7 +9,7 @@ mk() {
   mkdir -p "$r/.agents/baselines" "$r/pkg" "$r/tests/unit"
   printf '%s\n' "$r"
 }
-run() { local r="$1" s="$2"; shift 2; out="$(cd "$r" && env STUB_LOG="$r/stub.log" "$@" bash "scripts/sensors/$s.sh" 2>&1)"; rc=$?; }
+run() { local r="$1" s="$2"; shift 2; out="$(cd "$r" && env STUB_LOG="$r/stub.log" "$@" bash "$RUN_SENSOR" "scripts/sensors/$s.sh" 2>&1)"; rc=$?; }
 
 for s in typecheck lint tests; do
   f="$KEEL/skills/$SD/$s.sh"
diff --git a/tests/keel_rule_sensors_test.sh b/tests/keel_rule_sensors_test.sh
index 9c0da80..f5b5a9d 100644
--- a/tests/keel_rule_sensors_test.sh
+++ b/tests/keel_rule_sensors_test.sh
@@ -15,7 +15,7 @@ mk() {
 put() { install_asset "$1" "$RS/$2.sh" "scripts/sensors/$2.sh"; }
 run() { # run REPO SENSOR [env...] -> out, rc
   local r="$1" s="$2"; shift 2
-  out="$(cd "$r" && env "$@" bash "scripts/sensors/$s.sh" 2>&1)"; rc=$?
+  out="$(cd "$r" && env "$@" bash "$RUN_SENSOR" "scripts/sensors/$s.sh" 2>&1)"; rc=$?
 }
 nlines() { seq 1 "$1" | sed 's/.*/x/'; }
 commit() { (cd "$1" && git add -A && git commit -q -m c); }
@@ -179,7 +179,7 @@ printf '%s\n' "$out" | grep -qx "$(printf 'src/a.ts\t4')"; check "code-language:
 printf '%s\n' "$out" | grep -q "^src/b.ts	[1-9]"; check "code-language: non-ASCII identifier flagged" $?
 run "$r" code-language; [ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q '^code-language	heuristic	fail	' && printf '%s\n' "$out" | grep -q '^  guidance: Rename the identifiers'; check "code-language: fails without baseline" $?
 run "$r" code-language KEEL_MEASURE=1 | cat >/dev/null
-(cd "$r" && KEEL_MEASURE=1 bash scripts/sensors/code-language.sh > .agents/baselines/code-language.tsv)
+(cd "$r" && KEEL_MEASURE=1 bash "$RUN_SENSOR" scripts/sensors/code-language.sh > .agents/baselines/code-language.tsv)
 run "$r" code-language; [ $rc -eq 0 ]; check "code-language: baselined passes" $?
 echo 'const calcula = 1;' >> "$r/src/a.ts"; run "$r" code-language; [ $rc -eq 1 ]; check "code-language: growth fails" $?
 run "$r" code-language SCOPE=src/b.ts; [ $rc -eq 0 ]; check "code-language: SCOPE honoured" $?
@@ -211,7 +211,7 @@ structure slow/mutation
 r="$(mk)"; mkdir -p "$r/scripts/sensors/slow"; install_asset "$r" "$RS/slow/mutation.sh" scripts/sensors/slow/mutation.sh
 printf "MUTATION_MIN_SCORE=70\n" > "$r/.agents/rules/testing-strategy.env"
 mkdir -p "$r/src/main/java/a"; echo c > "$r/src/main/java/a/Foo.java"; commit "$r"
-runm() { local rr="$1"; shift; out="$(cd "$rr" && env STUB_LOG="$rr/stub.log" "$@" bash scripts/sensors/slow/mutation.sh 2>&1)"; rc=$?; }
+runm() { local rr="$1"; shift; out="$(cd "$rr" && env STUB_LOG="$rr/stub.log" "$@" bash "$RUN_SENSOR" scripts/sensors/slow/mutation.sh 2>&1)"; rc=$?; }
 runm "$r" SCOPE=src/main/java/a/Foo.java; [ $rc -eq 2 ]; check "mutation: tool absent -> skip" $?
 use_stub "$r" pitest-maven mvnw
 runm "$r" SCOPE=src/main/java/a/Foo.java STUB_OUT="Generated 10 mutations Killed 6 (60%)" STUB_EXIT=0
@@ -238,7 +238,7 @@ printf "DIFF_COVERAGE_MIN=80\n" > "$r/.agents/rules/testing-strategy.env"
 # src/a.ts has 4 lines; the report covers 1-3, not 4 (whole-file coverage 75%)
 mkdir -p "$r/coverage"; cp "$FIXTURES/coverage/lcov.info" "$r/coverage/lcov.info"; printf 'l1\nl2\nl3\nl4\n' > "$r/src/a.ts"; commit "$r"
 sed -i 's|^CMD=.*|CMD=(true)|' "$r/scripts/sensors/slow/diff-coverage.sh"
-rund() { local rr="$1"; shift; out="$(cd "$rr" && env "$@" bash scripts/sensors/slow/diff-coverage.sh 2>&1)"; rc=$?; }
+rund() { local rr="$1"; shift; out="$(cd "$rr" && env "$@" bash "$RUN_SENSOR" scripts/sensors/slow/diff-coverage.sh 2>&1)"; rc=$?; }
 sed -i '4s/.*/l4 changed/' "$r/src/a.ts"; rund "$r" SCOPE=src/a.ts
 [ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q '^diff-coverage	correctness	fail	diff coverage 0% .*(0 of 1 changed lines)' && printf '%s\n' "$out" | grep -qF '  src/a.ts: lines 4 not covered'; check "diff-coverage: the changed line 4 is uncovered -> fails and lists it" $?
 (cd "$r" && git checkout -q src/a.ts); sed -i '2s/.*/l2 changed/' "$r/src/a.ts"; rund "$r" SCOPE=src/a.ts
diff --git a/tests/keel_ts_sensors_test.sh b/tests/keel_ts_sensors_test.sh
index 81462bc..81876aa 100644
--- a/tests/keel_ts_sensors_test.sh
+++ b/tests/keel_ts_sensors_test.sh
@@ -14,7 +14,7 @@ mk() {
 }
 run() { # run REPO SENSOR [env...] -> sets out, rc
   local r="$1" s="$2"; shift 2
-  out="$(cd "$r" && env STUB_LOG="$r/stub.log" "$@" bash "scripts/sensors/$s.sh" 2>&1)"; rc=$?
+  out="$(cd "$r" && env STUB_LOG="$r/stub.log" "$@" bash "$RUN_SENSOR" "scripts/sensors/$s.sh" 2>&1)"; rc=$?
 }
 
 # --- structure
````

- [ ] **Step 4: verify.**
  - `KEEL_ENGINE=cli KEEL_BIN=/bin/false bash tests/keel_gate_test.sh | grep -c FAIL` → above zero (19 in the prototype): the CLI mode really runs the binary.
  - `KEEL_ENGINE=cli ./tests/run.sh > /tmp/cli.log; echo rc=$?` → `rc=0`; `grep -cE '^\s+ok ' /tmp/cli.log` → **N + 42**; `grep -c 'skip (cli)' /tmp/cli.log` → `1` (`missing envparse lib: skip`).
  - `./tests/run.sh; echo rc=$?` → `rc=0` with **N + 43** `ok` (the bash engine is unchanged).
  - `shellcheck -S warning tests/keel_helpers.sh tests/keel_run_sensor.sh tests/keel_cli_parity_test.sh` → no output.
- [ ] **Step 5: commit and push.** `test(keel-cli): run the existing gate and sensor tests through keel gate (KEEL_ENGINE=cli)`

---

## Task 5 — CI on both engines, `make check-cli`, reproducible builds

**Files:** modify `.github/workflows/validate.yml`, `Makefile`.

- [ ] **Step 1: see the gap.** `make check-cli; echo rc=$?` → make reports that it has no rule for `check-cli`, `rc=2`.
- [ ] **Step 2: apply.** Without the workflow change, CI would now fail: the Validate job runs with `CI=true`, which makes the two new tests require the binary.

Patch:

````diff
diff --git a/.github/workflows/validate.yml b/.github/workflows/validate.yml
index 900982d..f2ede63 100644
--- a/.github/workflows/validate.yml
+++ b/.github/workflows/validate.yml
@@ -9,8 +9,19 @@ jobs:
     runs-on: ubuntu-latest
     steps:
       - uses: actions/checkout@v4
+      - uses: actions/setup-go@v5
+        with:
+          go-version-file: cli/keel/go.mod
+      - name: Build and unit-test the keel CLI
+        run: make -C cli/keel test build
       - name: Run tests
         run: ./tests/run.sh
+      - name: Run tests on the keel CLI engine
+        run: KEEL_ENGINE=cli ./tests/run.sh
+      - name: keel builds are reproducible
+        run: |
+          make -C cli/keel dist && cp cli/keel/dist/engine/SHA256SUMS "$RUNNER_TEMP/sums"
+          go clean -cache && make -C cli/keel dist && diff "$RUNNER_TEMP/sums" cli/keel/dist/engine/SHA256SUMS
       - name: Install Claude Code
         run: npm i -g @anthropic-ai/claude-code
       - name: Validate plugin
diff --git a/Makefile b/Makefile
index 8123e46..20444da 100644
--- a/Makefile
+++ b/Makefile
@@ -1,8 +1,14 @@
-.PHONY: check validate
+.PHONY: check check-cli validate
 
 check:
 	./tests/run.sh
 
+# The keel CLI (cli/keel): its unit tests, then the whole suite on both engines.
+check-cli:
+	$(MAKE) -C cli/keel test build
+	./tests/run.sh
+	KEEL_ENGINE=cli ./tests/run.sh
+
 validate:
 	claude plugin validate ./plugins/keel-harness --strict
 	claude plugin validate ./plugins/solutions-architect --strict
````

- [ ] **Step 3: verify.**
  - `make check-cli > /tmp/cc.log; echo rc=$?` → `rc=0`; `grep -cE '^\s+ok ' /tmp/cc.log` → **2N + 85** (both engines).
  - `make -C cli/keel dist && cp cli/keel/dist/engine/SHA256SUMS /tmp/sums && go clean -cache && make -C cli/keel dist && diff /tmp/sums cli/keel/dist/engine/SHA256SUMS && echo reproducible` → `reproducible`.
- [ ] **Step 4: commit and push.** `ci(keel-cli): build the CLI and run the suite on both engines`
- [ ] **Step 5: CI.** `gh run list --branch "$(git branch --show-current)" --limit 1` → the Validate run of this commit is `completed  success`. This is the only check the workflow file gets; if it fails, read the log (`gh run view --log-failed`) and report.

---

## Task 6 — acceptance and report

- [ ] **Step 1: the F1 acceptance criteria**, each with its evidence:
  1. **The existing sensor tests run through `keel gate`:** `KEEL_ENGINE=cli ./tests/run.sh` → rc 0, N + 42 `ok`, exactly one `skip (cli)`. Every gate test runs `keel gate`, every sensor test runs `keel gate --sensor <id>` (Task 4, Step 4, first bullet proves the binary is used).
  2. **Byte parity with `gate.sh`:** `CI=1 bash tests/keel_cli_parity_test.sh` → 9 `ok`.
  3. **Contract kept:** the 34 `keel_cli_test.sh` checks; `guard`'s 24 checks of `tests/keel_guard_test.sh` on the CLI engine (23 `ok` + 1 `skip (cli)`).
  4. **Nothing in the plugin changed:** `git diff --stat <base> -- plugins/` → no output.
  5. **Reproducible:** Task 5, Step 3, second bullet.
- [ ] **Step 2:** `make validate` → `Validation passed` for the three plugins.
- [ ] **Step 3: report to the owner:** the commit list; the counts of acceptance 1–3; any step whose output differed from this plan; anything skipped and why. Do not open a pull request; do not start F2.

---

## Later phases (outline; each gets its own executable plan when the previous one is done)

### F2 — native entry points

`keel check` (port of `harness-check.sh`; conformance: `tests/keel_harness_check_test.sh` and `tests/doctor_test.sh` on the CLI engine,
plus `pin` and `sensor-unlisted` findings that `keel validate` already computes) and `keel hook claude-stop` (port of `claude-stop.sh`;
conformance: `tests/keel_stop_hook_test.sh` on the CLI engine, the hook's JSON byte for byte). Acceptance: the suite on the CLI engine
stays green with `harness-check.sh` and `claude-stop.sh` replaced by the CLI in the test shims.

### F3 — native adapters, one at a time (`eslint-json` first)

Each adapter is one plan with the same tasks: (1) the adapter's `keel.yaml` fields — `run` as an argv list with `{scope}`,
`scope_default`, the file filter, `baseline`, `guidance` — in `config`, the schema and `Validate`; (2) `importer` translates the wrapper's
`keel:repo-specific` block into that entry; (3) the wrapper's existing test file runs **unchanged** on the CLI engine against the native
adapter; (4) a parity case runs the wrapper and the adapter on the same stub output and compares line 1, details and exit code byte for byte;
(5) `guard` treats a dropped adapter entry like a removed sensor (already true by id). The queue, with the tests that become each
adapter's conformance suite:

| Wrapper | Class | Adapter | Conformance tests |
| --- | --- | --- | --- |
| `typescript/lint.sh` | heuristic, TSV baseline | `eslint-json` | `keel_ts_sensors_test.sh` (lint) |
| `typescript/typecheck.sh`, `tests.sh` | correctness | `tsc`, `vitest`/`jest` | `keel_ts_sensors_test.sh` |
| `common/secrets.sh` | security | `gitleaks` | `keel_ts_sensors_test.sh` (secrets) |
| `python/lint.sh`, `typecheck.sh`, `tests.sh` | heuristic / correctness | `ruff`, `mypy`/`pyright`, `pytest` | `keel_python_sensors_test.sh` |
| `jvm/compile.sh`, `lint.sh`, `tests.sh` | correctness / heuristic | `gradle`/`maven`, `ktlint`/`detekt`/`checkstyle`, `junit` | `keel_jvm_sensors_test.sh` |
| rule sensors: `file-size`, `folder-layout`, `code-language`, `test-presence`, `architecture`, `architecture-grep`, `slow/diff-coverage`, `slow/mutation` | as today | one adapter each | `keel_rule_sensors_test.sh` |

### F4 — plugin integration (binary-only)

`make -C cli/keel dist` writes `plugins/keel-harness/engine/<os>-<arch>/keel` and `engine/SHA256SUMS`, committed per release, and CI
rebuilds them and compares bytes; `build` gains the engine choice (bash | CLI) and, after confirmation, copies the binary to
`~/.local/share/keel/<version>/keel`, links `~/.local/bin/keel`, runs `keel import --sums`, deletes the replaced files (`scripts/gate.sh`,
`.agents/gate.env`, wrappers with a native adapter, then `harness-check.sh` and `claude-stop.sh` once F2 is in), writes the one-line
Makefile aliases, the `AGENTS.md` commands and the Stop hook as `keel hook claude-stop`; `doctor` runs `keel validate` and proposes moving
the pin when the plugin's engine is newer (the pin follows the plugin). Evals keep `make gate-fast` through the aliases.

## Risks

| Risk | Mitigation |
| --- | --- |
| Binary-only contradicts v0.3 §2.3 and D5 | The gating ADR supersedes them for CLI-engine repositories; the bash engine stays available |
| Engine binaries grow the marketplace's history: measured 2.7–2.9 MB per binary, 1.13–1.25 MB compressed, about **4.7 MB per release** for four platforms, against a 5.8 MB repository today; everyone who adds the marketplace clones it | Release the engine only when it changes; F4 reconsiders Git LFS or a release branch if the history passes an agreed size |
| The pin follows the plugin: a plugin update fails the gate (exit 3) in every repository still pinned to the old engine | `doctor` names the fix; `build` moves the pin; the failure is loud, never a pass |
| Name collision: v0.3 D34 reserves `${CLAUDE_PLUGIN_ROOT}/scripts/keel` for the plugin's phase CLI (`plan | approve | apply | verify | measure | check`), and `measure`/`check` mean something else here | Decide in v0.3 F2 whether the phase CLI becomes subcommands of the engine or is renamed |
| v0.3 F2 moves run state to `.agents/run/` (D39) | The parity test fails until the CLI follows — the intended alarm; the log path is one function (`gate.LogPath`) |
| A sensor that depends on locale order | Known difference 1; the contract says `SCOPE` is a list |
| `go.yaml.in/yaml/v3` is a fork | It is the YAML organization's maintained continuation of the archived `gopkg.in/yaml.v3`; one dependency, pinned in `go.sum` |
