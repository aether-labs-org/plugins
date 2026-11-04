# kh

keel's deterministic execution engine (v0.4), milestone M0: run any command from the repository root with
a process group and a timeout, keep the evidence, print a short verdict. Standard library only, Linux and
macOS, no network and no model call. Design: `docs/specs/2026-11-03-keel-cli-v0.4-design.md`.

## Commands

| Command | What it does |
| --- | --- |
| `kh run [--timeout D] [--json] -- <command...>` | Runs the command from the repository root (the nearest directory above the current one that holds `.agents/keel.yml`), captures stdout and stderr in order, redacts secrets, stores the evidence and prints a verdict. `--timeout` takes a Go duration (default `10m`); flags must come before `--`. |
| `kh show <id>` | The verdict of a stored run, recomputed from its log. |
| `kh show <id> --failures` | Only the lines that match the error vocabulary, with two lines of context (`<N>: <text>`). |
| `kh show <id> --full` | The redacted `output.log`, verbatim. |
| `kh show <id> --json` | `meta.json` (the same document as `kh run --json`). |
| `kh version` | `kh <version>`. |

## Exit codes of `kh run`

| Code | Status | When |
| --- | --- | --- |
| 0 | `pass` | the command exited 0 |
| 1 | `fail` | the command exited non-zero (a tool's own exit 2 is still `fail`) |
| 2 | `skip` | the command was not found (`run: make bootstrap`) |
| 3 | `error` | timeout (SIGTERM to the process group, SIGKILL after 5 s), cannot start, interrupted by Ctrl-C, or no `.agents/keel.yml` found |
| 64 | | bad usage; also `kh show` with an unknown or malformed id |

## Evidence

Each run is stored in `.agents/run/runs/<id>/` (`<id>` is `YYYYMMDD-HHMMSS-<4 hex>`, UTC): `meta.json` (the
result: command, status, exit code, timings, `HEAD` and a hash of the uncommitted diff, `kh` version) and
`output.log`. At most 50 runs and 200 MB are kept; the oldest are removed after each run. The directory is
local evidence: never commit it.

Redaction is best effort: values of environment variables whose names look secret (`*TOKEN*`, `*SECRET*`,
`*PASSWORD*`, `*CREDENTIAL*`, `*_KEY`, values of 6 bytes or more), AWS access keys, GitHub tokens, JWTs and
`PRIVATE KEY` blocks become `‹redacted›` in the log, in `meta.json` and on stdout.

## Scope of M0

`.agents/keel.yml` is only located, not parsed: scripts, gates, formats and baselines arrive in later
milestones. The output reduction is generic: the first 5 lines that match an error vocabulary and the last
10 lines.

## Build and test

```
make -C cli/kh build   # dist/kh
make -C cli/kh test    # gofmt, go vet, go test
bash tests/kh_test.sh  # end to end, through the built binary
```
