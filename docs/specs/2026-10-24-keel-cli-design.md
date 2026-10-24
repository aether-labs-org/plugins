# keel CLI — Design Spec (exploratory)

**Date:** 2026-10-24
**Status:** proposed — exploratory, not scheduled. v0.3 keeps the copied bash engine
(`2026-10-23-keel-harness-v0.3-design.md`, D48).
**Origin:** owner question, 2026-10-24: could the installed scripts be replaced by a CLI that reads
a declarative configuration file?

---

## 1. Problem

Every repository that keel installs into receives a copy of the same engine (`gate.sh`,
`harness-check.sh`, `lib/`) and of each sensor wrapper. Only the block between the
`keel:repo-specific` markers differs: tool path, arguments, paths and guidance text. Copies drift:
`doctor` already compares the installed `harness-check.sh` with the plugin's (`cmp`), and every
engine fix has to be re-copied into every repository.

## 2. Proposal

A versioned `keel` executable that runs the gates and the validator from a declarative file:

```yaml
# .agents/keel.yaml
version: 1
gate:
  fast: { ceiling_seconds: 30 }
  slow: { ceiling_seconds: 600 }
sensors:
  - id: typecheck
    class: correctness
    gate: fast
    run: node_modules/.bin/tsc --noEmit -p tsconfig.json
    scope: whole-repo            # the tool has no file-level mode
    pass_when: exit-0
    guidance: >-
      Fix the first type error; never widen a type to any to silence it.
  - id: lint
    class: heuristic
    gate: fast
    adapter: eslint-json          # built-in parser of the tool's output into per-file counts
    run: node_modules/.bin/eslint -f json {scope|src}
    baseline: .agents/baselines/lint.tsv
    guidance: >-
      Clear the new problems in the files you touched; never raise the baseline.
  - id: legacy-check
    gate: fast
    exec: scripts/sensors/legacy-check.sh   # any file that obeys the v0.2 sensor contract
rules_dir: .agents/rules
adr_dir: docs/adr
```

Commands: `keel gate fast|slow`, `keel check` (today's `harness-check`), `keel measure <id>`
(today's `KEEL_MEASURE=1`), `keel guard`, `keel validate` (schema). Output keeps the v0.2 sensor
contract byte for byte — line 1 `id<TAB>class<TAB>status<TAB>summary`, at most 5 detail lines,
`guidance:` on fail, exit 0/1/2 — so agents, graders, hooks and CI read it unchanged.

## 3. Trade-offs

| | Copied bash (v0.3) | CLI + YAML |
| --- | --- | --- |
| Engine updates | Re-copy into each repository; drift detection needed | Bump one pinned version |
| Runs with nothing installed | Yes: any bash 3.2, CI, pre-commit, any agent's container | No: the binary must be installed in dev, CI and every agent environment |
| Single source of configuration | Mixed with code in each wrapper | One file, schema-validated |
| Legibility for the agent | The wrapper shows what runs | The YAML shows what runs; parsing logic lives in the binary |
| Supply chain | Code visible in the repository | A pinned binary with a checksum, or a vendored copy |
| Cost | Exists: ~3,100 lines, 946 assertions | A rewrite of the engine and its tests, plus distribution |

## 4. When it pays off

Start this work only when at least one holds, and record which one in an ADR:

- keel runs in enough repositories that re-copying engine fixes costs more than distributing a binary;
- `doctor` reports engine drift as a recurring finding;
- the owner can require the binary everywhere the gate runs.

## 5. Design constraints

1. **Contract compatibility.** Output, exit codes, `SCOPE` semantics, baselines (TSV and native) and
   rule env files stay as v0.3 defines them. A repository can switch engines without editing
   `AGENTS.md`, hooks or CI beyond the command name.
2. **`exec` escape hatch.** Any existing sensor file that obeys the contract runs unchanged, so
   migration is per sensor, never all at once.
3. **No network, no model call** at gate time, as today.
4. **Fallback.** `make gate-fast` keeps working: the Makefile target calls `keel` when it is
   installed and fails with an install hint otherwise — never a silent pass.
5. **Pinned.** The version lives in `.agents/keel.yaml` (`requires: ">=1.2,<2"`); a mismatch is a
   `fail`, not a warning.
6. **Plugin portability.** The binary is distributed outside the plugin's `bin/` directory, which
   claude.ai and Cowork refuse to install (plugins reference).

## 6. Migration

1. Ship the CLI with the `exec` adapter only: `keel gate` runs the existing sensor files.
2. Add built-in adapters (eslint-json, junit, ruff, pytest, gitleaks …) one at a time; each moves one
   wrapper into YAML, with the wrapper's tests ported as fixtures.
3. `build` gains an engine choice (bash or CLI); `doctor` checks the pinned version.

## 7. Open questions

| Question | Options | Current lean |
| --- | --- | --- |
| Implementation language | Go (one static binary), Node (npm, already present in JS repositories), Python (pipx) | Go, for zero runtime dependencies — opinion, not measured |
| Distribution | GitHub releases + checksum, package managers, vendored binary in the repository | Releases + checksum, with an optional vendored copy for air-gapped CI |
| Config format | YAML, JSON, TOML | YAML with a published JSON Schema |
| Where `keel.yaml` lives | `.agents/keel.yaml`, repository root | `.agents/keel.yaml`, beside the rest of keel's committed configuration |
