# kh

keel's deterministic execution engine. One static binary per platform (Linux and macOS, amd64 and
arm64), pinned per repository, no network and no model call at gate time. Every verdict comes from an
exit code, a parser or a baseline, never from a model.

## What it does

- Runs the scripts declared in `.agents/keel.yml` (`kh run <script>`) and groups them into gates (`kh gate fast`),
  with timeout, retries, change scoping, a report parser per format (junit, sarif, checkstyle, eslint-json,
  errorformat), TSV baselines (a ratchet) and evidence of every run.
- Carries the builtins a project needs without any plugin: `guard`, `file-size`, `code-language`,
  `folder-layout`, `pattern`, `architecture-grep`, `test-presence`, `dependencies`, `memory`, `scope`,
  `merge-check`, `commit-message`, `branch-name`.
- Runs the agent hooks (`kh hook pre-tool-use | stop`) and the git hooks (`kh gate commit`, `kh hook commit-msg`)
  for Claude Code, GitHub Copilot CLI and Devin CLI, through one hook file, `.claude/settings.json`.
- Reports drift of the harness itself (`kh check`) and prepares a clone (`kh setup`).

## Commands

| Command | What it does |
| --- | --- |
| `kh run <script> [-- extra args]` | One declared script. Extra arguments are appended, each as one word. |
| `kh run [--timeout D] [--json] -- <command...>` | Any command: capture, verdict from the exit code, generic reduction. |
| `kh gate <name> [--all] [--json]` | The gate's scripts, in order, under a lock. `--all` passes every tracked or untracked (not ignored) file instead of the changed ones. |
| `kh show <id> [--failures \| --full \| --json]` | A stored run or gate. |
| `kh measure <script>` | Per-file counts as a TSV baseline on stdout. Never writes a file. |
| `kh validate` | Strict validation of `keel.yml`. Silent and exit 0 when valid; one line per issue and exit 3 otherwise. |
| `kh check [--strict] [--measure]` | Warnings about the harness (`agents-size`, `hook-missing`, `githooks-inactive`, `baseline-stale`, ...). `--strict` exits 1 on any warning. |
| `kh guard` | The `guard` script alone: did the harness get loosened since the base? |
| `kh hook pre-tool-use [--setup] \| stop \| commit-msg <file>` | The hook entry points. The agent hooks always exit 0. |
| `kh setup` | Per clone: activate the native git hooks (`core.hooksPath`), then run `kh check`. |
| `kh schema keel \| result \| memory` | The JSON Schemas (the single contract source). |
| `kh version` | `kh <version>`. |

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | pass |
| 1 | fail (`kh gate` also exits 1 when a `class: security` script was skipped) |
| 2 | skip (no changed file in scope, a missing tool, no base commit yet) |
| 3 | error: invalid config, pin mismatch, timeout, an unreadable report, no repository |
| 64 | bad usage |

## Distribution

The repository carries `.agents/bin/kh` (a POSIX `sh` wrapper, `wrapper/kh` here) and `.agents/keel.lock`
(the version and the sha256 of each platform's binary). The wrapper downloads the pinned binary once into
`$XDG_CACHE_HOME/keel/<version>/kh` (macOS `~/Library/Caches/keel/`), verifies it against the lock and
execs it. `KH_BINARY` (verified against the lock too) and `KH_RELEASE_URL` (a mirror) override the
source. In hook mode the wrapper never downloads: without a verified binary it answers `ask` (`deny`
under `bypassPermissions`/`dontAsk`) for PreToolUse and a non-blocking notice for Stop.

```
make -C cli/kh dist VERSION=0.5.0     # dist/kh-<os>-<arch> and dist/SHA256SUMS, byte-identical on a rebuild
make -C cli/kh lock VERSION=0.5.0     # prints a keel.lock from dist/SHA256SUMS
```

Releases are tags `cli/kh/vX.Y.Z` (pre-releases `-rc.N`) pushed by the owner;
`.github/workflows/release-kh.yml` tests, builds, attests and publishes them.

## Evidence

Each run is stored in `.agents/run/runs/<id>/` (`<id>` is `YYYYMMDD-HHMMSS-<4 hex>`): `meta.json` (the
result, the same document as `--json`), `output.log` and copies of the declared reports; a gate adds a
`gate.json`. At most 50 runs and 200 MB are kept. The directory is local: never commit it. Redaction is best
effort: secret-looking environment values, AWS keys, GitHub tokens, JWTs and private-key blocks become
`‹redacted›` in the log, in `meta.json` and on stdout.

## Recorded fixtures

`testdata/formats/` holds real output of the tools whose format kh parses, with the exact command and the
tool version that produced it (`README.md` there lists them). `testdata/hooks/` holds hook payloads built
from the documented shapes.

## Build and test

```
make -C cli/kh build    # dist/kh
make -C cli/kh test     # gofmt, go vet, go test
bash tests/kh_test.sh   # end to end, through the built binary
bash tests/kh_wrapper_test.sh   # wrapper, dist, kh setup
```

Design: `docs/specs/2026-11-04-keel-harness-v0.5-design.md`.
