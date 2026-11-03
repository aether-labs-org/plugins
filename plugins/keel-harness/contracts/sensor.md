# Sensor contract — the seven fields, the classes, and the wrapper protocol

A **sensor** is a computational check the agent can run itself and read the answer of without a
human. Every sensor this kit installs is a small shell file in `scripts/sensors/` (fast) or
`scripts/sensors/slow/` (slow) that runs a tool the repository already has and translates its
output into one fixed shape. The shape is what makes the gate legible to an agent: same first line,
same exit codes, same place to look for what to do next, whatever the language or the tool
underneath.

**The wrappers are tested files, not templates.** They ship under `assets/core/` (stack
sensors, the gate runner, the baseline library) and `assets/core/sensors/rules/` (rule sensors). `build`
and `rules` copy them and edit only the block between the `keel:repo-specific` markers. Never
regenerate a wrapper from this document; this document explains the contract those files obey.

---

## 1. The seven fields

| # | Field | What it means | Where it lives |
| --- | --- | --- | --- |
| 1 | **pass signal** | The exact, literal output that means "clean". An agent never has to judge whether output *looks* good. | line 1 `status` (`pass`) and its one-line summary |
| 2 | **guidance** | On failure, what to do next **in the repository's own terms** - which file, which decision, what action. Never a restatement of the tool's error. | the `guidance: ` block on `fail` |
| 3 | **scope** | What the sensor looked at: the changed files (`SCOPE`) or the whole repository. A sensor whose tool has no file-level mode says so. | `SCOPE` in, the summary out |
| 4 | **cost** | Wall time in milliseconds, measured by `gate.sh` from outside. The money cost of the gates is **US$0.00**, with one opt-in exception: `slow/reviewer.sh` (section 7) calls the model its user configured, and the slow gate's verdict line then says so instead of printing `US$0.00`. | `gate.sh` report |
| 5 | **bounded verbosity** | At most 5 detail lines per sensor, indented two spaces; `gate.sh` truncates its stdout at 40 lines and keeps the full run in `.agents/run/last-run.log` (`.agents/run/last-run-slow.log` for the slow gate). | the sensor, then `gate.sh` |
| 6 | **class** | `security`, `correctness` or `heuristic` (section 2). | line 1 |
| 7 | **ceiling** | `CEILING_SECONDS` (default 30) and `SLOW_CEILING_SECONDS` (default 600) in `.agents/gate.env`. The total over the budget is flagged `(over ceiling)`; a sensor that alone blows the fast budget is left out or moved to the slow gate, and `.agents/state.yml` says which and why. | `.agents/gate.env` |

## 2. The three classes and baselines

| Class | Examples | Baseline allowed? |
| --- | --- | --- |
| **security** | secret scanning | **never** |
| **correctness** | types, affected tests, architecture | only the tool's native baseline, and only for a rule adopted after the code existed (an ADR and a plan back it) |
| **heuristic** | lint, file size, code language, test presence | yes: a per-file TSV baseline |

A `security` sensor fails on the first problem, full stop: it never reads a baseline and has no
threshold. "We only have three leaked keys, same as yesterday" is not a passing state.

**A baseline is a comparison, not a label.** A baselined sensor takes its `status` from comparing
the current per-file counts with the baseline, never from the tool's raw exit code.

### TSV baselines (keel's own)

`.agents/baselines/<id>.tsv`. First line `# measured_at: YYYY-MM-DD review_by: YYYY-MM-DD` (six
months out), then `path<TAB>count`. Meaning: this file may keep up to `count` violations; a file
absent from the baseline may have zero. A sensor fails when any file exceeds its count; shrinking
is always allowed. The comparison lives in `scripts/lib/baseline.sh` (`baseline_compare`).

- Sensors **never write** baselines. Every TSV-baselined sensor supports `KEEL_MEASURE=1`, which
  prints the header and the current non-zero counts and exits 0; that output is what `build` or
  `rules` writes at approval time (`KEEL_MEASURE=1 bash scripts/sensors/<id>.sh > .agents/baselines/<id>.tsv`).
- Because baselines are per file, a baselined sensor may honour `SCOPE` and look only at the files
  that changed.
- Only keel writes or tightens a baseline, with the user's approval. It never raises one. `guard` fails a
  row that grew or appeared unless an ADR added in the same change names the baseline file.
- `review_by` is the ratchet's expiry. Past it, `harness-check.sh` warns (`baseline-stale`) unless
  the total has dropped; re-measure downward, never upward to accommodate drift.

### Native baselines

When the tool has its own, use it instead of a TSV: ArchUnit's `FreezingArchRule` (store under
`.agents/baselines/archunit/` via `archunit.properties`), dependency-cruiser's known-violations file
`.agents/baselines/depcruise-known-violations.json` (`--ignore-known`), import-linter's
`ignore_imports`. Such a sensor answers `KEEL_MEASURE=1` with `# native baseline - see
docs/architecture.md#architecture`.

---

## 3. The wrapper protocol

Every sensor file written into a user repository:

- reads the environment variable **`SCOPE`**, a newline-separated list of changed files (**empty
  means the whole repo**; deleted files are excluded);
- writes **line 1** to stdout as four tab-separated fields:
  `<id>\t<class>\t<status>\t<summary>`, where `class` is `security|correctness|heuristic` and
  `status` is `pass|fail|skip`;
- writes at most 5 detail lines **indented by two spaces**, and on `fail` a block starting
  `guidance: ` saying what to do in the user's repository terms;
- exits **`0` on pass, `1` on fail, `2` on skip** (the tool is not installed - **never** a silent
  pass).

Rules that follow from it:

- **Line 1 is `printf '%s\t%s\t%s\t%s\n' "$id" "$class" "$status" "$summary"`** - `id`, `class`,
  `status`, `summary`, in that order. `gate.sh`, the graders and `assess` `cut -f1..4` in that order.
  The sensor does not print its own elapsed time.
- **`id=` equals the file name without `.sh`.** The gate takes the id from the file name.
- **Discovery.** `gate.sh fast` runs the top-level `scripts/sensors/*.sh`; `gate.sh slow` runs
  `scripts/sensors/slow/*.sh`; both sorted by name. Files starting with `_`, subdirectories
  (`disabled/`, `stoplists/`) and non-`.sh` files never run. Moving a sensor to
  `scripts/sensors/disabled/` turns it off.
- **Honour `SCOPE`**; do not print a fixed scope string. Fall back to the whole repo only when
  `SCOPE` is empty or the tool has no file-level mode (say so).
- **The summary is one line** and states the pass signal in the tool's numbers.
- **A missing tool is a `skip`**, with what is missing and how to get it (usually `make bootstrap`).
- **`guidance:` appears only on `fail`** and never paraphrases the error: the error says *what*
  broke; guidance says what is done about it here, and which plausible fix is the wrong one.
- **A temporary file or directory comes from `TMPDIR`, else from a fresh directory under
  `.agents/run/tmp/`** (git-ignored, removed on exit), **else the sensor skips** with the summary
  `no writable temp directory (TMPDIR or .agents/run/tmp/)` (`guard` fails instead). Never write
  `"$tmp/..."` with an empty `tmp`: it lands at the filesystem root.
- **A sensor never `cd`s.** `gate.sh` runs every sensor from the repository root.
- **Never `set -e` past the tool call**: translate a non-zero tool exit, do not die of it.
- **No network, no model call, no plugin paths** (sections 5 and 6). The one exception is `slow/reviewer.sh` (section 7).

Check field order explicitly, not just field count: a line 1 of `fail<TAB>typecheck<TAB>correctness<TAB>1.06s`
has four fields but corrupts every downstream reader.

## 4. The repo-specific block

Each stack sensor keeps everything repository-specific between two markers:

```
# --- keel:repo-specific begin ---
...tool path, arguments, paths, GUIDANCE text...
# --- keel:repo-specific end ---
```

`build` and `rules` edit only inside the block, using commands found in discovery. A future
`build` run may replace everything outside the markers with the plugin's newer copy.

## 5. Assets, by stack

| Asset (under `${CLAUDE_PLUGIN_ROOT}/assets/core/`) | Class | Installed as |
| --- | --- | --- |
| `gate.sh`, `gate.env` | - | `scripts/gate.sh`, `.agents/gate.env` |
| `lib/baseline.sh` | - | `scripts/lib/baseline.sh` |
| `lib/envparse.sh` | - | `scripts/lib/envparse.sh` (reads rule and gate env files; never executes them) |
| `sensors/typescript/typecheck.sh` | correctness | `scripts/sensors/typecheck.sh` |
| `sensors/typescript/lint.sh` | heuristic, TSV baseline | `scripts/sensors/lint.sh` |
| `sensors/typescript/tests.sh` | correctness | `scripts/sensors/tests.sh` |
| `sensors/common/secrets.sh` | security, no baseline | `scripts/sensors/secrets.sh` |
| `sensors/common/guard.sh` | security, no baseline | `scripts/sensors/guard.sh` (fails when the harness was loosened without an ADR) |
| `sensors/slow/journey.sh` | correctness, opt-in, experimental | `scripts/sensors/slow/journey.sh` (Playwright journeys, `profile-l.md`) |
| `sensors/slow/reviewer.sh` | heuristic, opt-in, experimental | `scripts/sensors/slow/reviewer.sh` (a model reviews the diff, section 7) |

Python, Java/Kotlin and rule sensors are listed in `sensors-by-language.md` and in the `rules`
catalog. The `rules` skill ships its own sensors under its `assets/sensors/` (slow ones install to
`scripts/sensors/slow/`).

## 6. Portability

Installed scripts are plain `bash` (3.2-compatible, no `jq`) that live in the user's repository and
must run identically with this plugin absent: no `${CLAUDE_*}` variable, no path into the plugin
directory, no `claude` invocation, no network call (the opt-in `slow/reviewer.sh` runs the user's own
`REVIEWER_CMD`, section 7). Verify it by running `make gate-fast` in a
shell that has never heard of the plugin.

## 7. The one sensor that calls a model: `slow/reviewer.sh` (profile L, experimental)

`assets/core/sensors/slow/reviewer.sh` (class `heuristic`) is the only installed script allowed to
call a model, and only through `REVIEWER_CMD`, the command the user wrote into
`.agents/rules/reviewer.env`. keel names no model and ships no key; the user decides what runs and what it costs.
It lives in `scripts/sensors/slow/` only: the fast gate and the Stop hook never run it, and a test greps
every other installed script for a model or network call. It follows the protocol of section 3 with these specifics (keys, prompt and calibration: `profile-l.md`):

- **Opt-in.** No `reviewer.env`, an empty `REVIEWER_CMD`, or a command not on `PATH` is a `skip`.
- **Input.** The diff since the base (`KEEL_GUARD_BASE`, else the merge-base with `origin/HEAD`, else
  `HEAD`, as `guard`; `SCOPE` is not used), `AGENTS.md`, and every docs section `AGENTS.md` cites. They go
  to `REVIEWER_CMD` on stdin, so the diff leaves the machine.
- **Budget.** `MAX_DIFF_LINES` (default 800; a larger diff is a `skip`) and `TIMEOUT_SECONDS` (default 120;
  a command still running then is stopped and the sensor `skip`s).
- **Verdict.** Lines `PASS` or `FAIL: <reason>`. Any `FAIL` line fails (at most 5 are printed). A reply with
  neither, an empty reply, a non-zero exit or a timeout is a `skip`: **never a pass**.
- **Cost.** Every `make gate-slow` with the file present is one model call. When it ran, the verdict line of
  the slow gate says `model cost: reviewer sensor ran ...` rather than `US$0.00`.
- **Status.** Experimental and unproven (D52) until a with/without measurement shows a gain.
