# bmax

Baymax's deterministic execution engine. One static binary per platform (Linux and macOS, amd64 and
arm64), pinned per repository, no network and no model call at gate time. Every verdict comes from an
exit code, a parser or a baseline, never from a model.

## What it does

- Runs the scripts declared in `.agents/bmax.yml` (`bmax run <script>`) and groups them into gates (`bmax gate fast`),
  with timeout, retries, change scoping, a report parser per format (junit, sarif, checkstyle, eslint-json,
  errorformat), TSV baselines (a ratchet) and evidence of every run.
- Carries the builtins a project needs without any plugin: `guard`, `file-size`, `code-language`,
  `folder-layout`, `pattern`, `architecture-grep`, `test-presence`, `dependencies`, `memory`, `scope`,
  `merge-check`, `commit-message`, `branch-name`.
- Runs the agent hooks (`bmax hook pre-tool-use | stop`) and the git hooks (`bmax gate commit`, `bmax hook commit-msg`)
  for Claude Code, GitHub Copilot CLI and Devin CLI, through one hook file, `.claude/settings.json`.
- Reports drift of the harness itself (`bmax check`) and prepares a clone (`bmax setup`).

## Commands

| Command | What it does |
| --- | --- |
| `bmax run [--all] <script> [-- extra args]` | One declared script. Extra arguments are appended, each as one word. `--all` runs it over every tracked or untracked (not ignored) candidate file, as `bmax gate <name> --all` does, instead of the changed ones. |
| `bmax run [--timeout D] [--json] -- <command...>` | Any command: capture, verdict from the exit code, generic reduction. |
| `bmax gate <name> [--all] [--json]` | The gate's scripts, in order, under a lock. `--all` passes every tracked or untracked (not ignored) file instead of the changed ones. |
| `bmax show <id> [--failures \| --full \| --json]` | A stored run or gate. |
| `bmax measure <script>` | Per-file counts as a TSV baseline on stdout. Never writes a file. |
| `bmax validate` | Strict validation of `bmax.yml`. Silent and exit 0 when valid; one line per issue and exit 3 otherwise. |
| `bmax check [--strict] [--measure]` | Warnings about the harness (`agents-size`, `hook-missing`, `githooks-inactive`, `baseline-stale`, ...). `--strict` exits 1 on any warning. |
| `bmax guard` | The `guard` script alone: did the harness get loosened since the base? |
| `bmax hook pre-tool-use [--setup] \| stop \| commit-msg <file>` | The hook entry points. The agent hooks always exit 0. |
| `bmax setup` | Per clone: activate the native git hooks (`core.hooksPath`), then run `bmax check`. |
| `bmax schema config \| result \| memory` | The JSON Schemas (the single contract source). |
| `bmax version` | `bmax <version>`. |

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | pass |
| 1 | fail (`bmax gate` also exits 1 when a `class: security` script was skipped) |
| 2 | skip (no changed file in scope, a missing tool, no base commit yet) |
| 3 | error: invalid config, pin mismatch, timeout, an unreadable report, no repository |
| 64 | bad usage |

## Distribution

The repository carries `.agents/bin/bmax` (a POSIX `sh` wrapper, `wrapper/bmax` here) and `.agents/bmax.lock`
(the version and the sha256 of each platform's binary). The wrapper downloads the pinned binary once into
`$XDG_CACHE_HOME/bmax/<version>/bmax` (macOS `~/Library/Caches/bmax/`), verifies it against the lock and
execs it. `BMAX_BINARY` (verified against the lock too) and `BMAX_RELEASE_URL` (a mirror) override the
source. In hook mode the wrapper never downloads: without a verified binary it answers `ask` (`deny`
under `bypassPermissions`/`dontAsk`) for PreToolUse and a non-blocking notice for Stop.

### Which repository a command works on

The wrapper of a repository (`.agents/bin/bmax`) exports `BMAX_ROOT=<that repository>`, overriding any inherited value; the plugin's
copy (`bmax/bin/bmax`) unsets it. `bmax` takes the root of a command from `BMAX_ROOT` when it is set (it must be the top-level of a git
work tree, else `bmax` exits 3), and otherwise from the git top-level of the working directory. An agent session can leave its
repository (`cd` into a nested repository or a worktree, which is another git repository); `BMAX_ROOT` keeps the commands, `bmax
hook stop` and the protected set on the project. `bmax hook pre-tool-use` checks each write target against the protected set of the
repository that contains the target (a repository without `.agents/bmax.yml` has none, except in `--setup` mode, which applies
the setup defaults), and intercepts declared scripts with the config of the repository the command runs in.
`BMAX_ROOT` is only the hand-off from the wrapper to the `bmax` process it execs: `bmax` removes it from the environment of every script and
command it runs, so a `bmax` binary started inside a script works on its own working directory. For the same reason `bmax` removes the repository-local git variables (`git rev-parse --local-env-vars`: `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_COMMON_DIR`, ...) that a git hook exports: a script that runs `git init`, `git config` or `git commit` in another directory must not act on the repository being committed or pushed. `bmax`'s own git calls keep the inherited environment, and the script still runs in the repository root.

```
make -C cli/bmax dist VERSION=0.5.0     # dist/bmax-<os>-<arch> and dist/SHA256SUMS, byte-identical on a rebuild
make -C cli/bmax lock VERSION=0.5.0     # prints a bmax.lock from dist/SHA256SUMS
```

Releases are tags `cli/bmax/vX.Y.Z` (pre-releases `-rc.N`) pushed by the owner;
`.github/workflows/release-bmax.yml` tests, builds, attests and publishes them.

## Evidence

Each run is stored in `.agents/run/runs/<id>/` (`<id>` is `YYYYMMDD-HHMMSS-<4 hex>`): `meta.json` (the
result, the same document as `--json`), `output.log` and copies of the declared reports; a gate adds a
`gate.json`. At most 50 runs and 200 MB are kept. The directory is local: never commit it. Redaction is best
effort: secret-looking environment values, AWS keys, GitHub tokens, JWTs and private-key blocks become
`‹redacted›` in the log, in `meta.json` and on stdout.

## Recorded fixtures

`testdata/formats/` holds real output of the tools whose format bmax parses, with the exact command and the
tool version that produced it (`README.md` there lists them). `testdata/hooks/` holds hook payloads built
from the documented shapes.

## Build and test

```
make -C cli/bmax build    # dist/bmax
make -C cli/bmax test     # gofmt, go vet, go test
bash tests/bmax_test.sh   # end to end, through the built binary
bash tests/bmax_wrapper_test.sh   # wrapper, dist, bmax setup
```

Design: `docs/specs/2026-11-04-baymax-harness-v0.5-design.md`.
