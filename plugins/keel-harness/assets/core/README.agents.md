# How to change this harness by hand

This file explains the harness keel-harness installed here, so a person or any agent can adjust it
without the plugin. Everything is plain files. After any change, run `make harness-check`: it prints
one `warn` line per broken condition, or `harness is clean`.

## Where things live

| Path | What it is | Edit by hand? |
| --- | --- | --- |
| `AGENTS.md`, `<dir>/AGENTS.md` | Instructions every agent reads: commands, "Before you finish", one line per rule. At most 100 lines each | Yes |
| `CLAUDE.md` | Contains `@AGENTS.md` so Claude Code loads the same instructions | Keep the import |
| `docs/architecture.md`, `docs/conventions.md`, `docs/testing.md` | Rule prose, one anchored section per rule (`<a id="rule-id"></a>`). At most 300 lines each | Yes |
| `<adr_dir>/NNNN-*.md` (`adr_dir` in `.agents/state.yml`, default `docs/adr/`) | ADRs: why a rule is the way it is. Never edit an accepted one; supersede it | Add new ones |
| `.agents/rules/<rule-id>.env` | A rule's metadata and parameters (`LIMIT`, `INCLUDE`, ...), read by its sensor | Yes |
| `.agents/baselines/<id>.tsv` | Violations that existed when a rule was adopted, per file | Only shrink |
| `.agents/baselines/archunit/`, `depcruise-known-violations.json` | Native architecture baselines (ArchUnit freeze store, dependency-cruiser known violations); import-linter's is `IGNORE_IMPORTS` in `architecture.env` | Only shrink |
| `.agents/gate.env` | `CEILING_SECONDS` and `SLOW_CEILING_SECONDS` | Yes |
| `.agents/state.yml` | Metadata only (`schema_version`, `mode`, `harness_review_by`, `adr_dir`) | Rarely |
| `.agents/run/` | Run state (logs, fingerprints, lock) and `tmp/`, the temp-dir fallback when `TMPDIR` is unusable; git-ignored | Never: delete it to reset |
| `.agents/plans/` | Plans (`Status: active/done/abandoned`, a required `## Acceptance`), committed; when done or abandoned, log one line in `.agents/progress.md` (the `keel plan-close` command does it) and delete the file | Yes |
| `.agents/progress.md` | What survives between sessions: one line per closed plan, plus notes for the next session. Committed; `harness-check` warns when it passes `PROGRESS_MAX_LINES` | Yes |
| `scripts/gate.sh` | Runs `make gate-fast` / `make gate-slow` | No (managed) |
| `scripts/lib/` | Helpers sourced by sensors (`baseline.sh`, `junit.sh`) | No (managed) |
| `scripts/sensors/*.sh` | Fast sensors, one per file | Yes |
| `scripts/sensors/slow/*.sh` | Slow sensors (mutation, diff coverage) | Yes |
| `scripts/sensors/disabled/` | Sensors switched off | Yes |
| `scripts/sensors/stoplists/` | Word lists for the code-language sensor | Yes |
| `scripts/hooks/claude-stop.sh` | Hands gate failures back to Claude Code | No (managed) |
| `.claude/settings.json` | Wires the Stop hook | Yes |
| generated tool config | `ArchitectureTest.java`, `.dependency-cruiser.cjs`, `.importlinter`: regenerated from `.agents/rules/architecture.env` | Edit the env, not the output |

Installed scripts start with a "Managed by keel-harness" line. Edit only between the
`# --- keel:repo-specific begin ---` and `# --- keel:repo-specific end ---` markers.

## Recipes

### Change a rule's limit
1. Edit the value in `.agents/rules/<rule-id>.env` (for example `LIMIT=400`).
2. Edit the same number in the rule's section in its topic file.
3. Run `make harness-check`; it flags a number that differs between the two.
4. Write an ADR in the ADR folder (`adr_dir`) if the change is a real trade-off. Loosening the limit (raising a
   `LIMIT`/`MAX`, lowering a `MIN`) always needs one: `guard` fails until an ADR added in the same
   change names `.agents/rules/<rule-id>.env`.

### Add a sensor
Drop an executable file in `scripts/sensors/` (fast) or `scripts/sensors/slow/` (slow). It must:
- print on line 1 `printf '%s\t%s\t%s\t%s\n' "$id" "$class" "$status" "$summary"`;
- set `id=` to the file name without `.sh` and `class=` to `security`, `correctness` or `heuristic`;
- exit 0 on pass, 1 on fail, 2 on skip (never a silent pass);
- print at most 5 detail lines indented by two spaces, and a `guidance: ` block only on failure;
- read `SCOPE` (changed files, newline separated; empty means the whole repository).
Files starting with `_` and subdirectories are never run by the gate.

### Disable a sensor
Move it to `scripts/sensors/disabled/`. The gate runs only top-level `*.sh` files. Move it back to
re-enable it. `make harness-check` warns when a rule still points at a sensor that is not in
`scripts/sensors/` or `scripts/sensors/slow/`. Disabling a committed sensor is a loosening: `guard`
fails until an ADR added in the same change names `scripts/sensors/<id>.sh`.

### Shrink a baseline after a fix
```bash
KEEL_MEASURE=1 bash scripts/sensors/<id>.sh > .agents/baselines/<id>.tsv
git diff .agents/baselines/<id>.tsv    # numbers must only go down
```
Never raise a baseline to make the gate pass. `security` sensors have no baseline. Native
architecture baselines shrink on their own (ArchUnit drops fixed violations from its store) or by
re-running `depcruise-baseline`; for import-linter, delete the fixed edge from `IGNORE_IMPORTS`.

### Add a rule by hand
1. Add an anchored section to the right topic file: `<a id="my-rule"></a>`, a `###` heading, then
   **Rule.**, **Why.**, **✓ / ✗.**, **When it fails.** and, when there is an ADR, **Decision.**
2. Copy an existing `.agents/rules/*.env` and set `RULE_ID`, `KIND`, `ORIGIN=user`, `APPROVED_AT`,
   `ENFORCEMENT` (`sensor:<id>` or `inferential`), `DOC=docs/<topic>.md#my-rule` and the parameters.
3. Add one line to `AGENTS.md`: `- <statement> → docs/<topic>.md#my-rule`.
4. Run `make harness-check`.

### Record a decision
Copy an existing ADR in the ADR folder (`adr_dir`; MADR: context, decision drivers, considered options,
outcome, consequences, evidence), number it `NNNN`, and link it from the rule's **Decision.** line
and `DECISION=` key. To change a decision, write a new ADR that supersedes the old one.

### Turn the Stop hook off
Remove the `Stop` entry from `.claude/settings.json`. Copilot and Devin never had a hook; they follow
"Before you finish" in `AGENTS.md`. `make harness-check` will warn (`hook-missing`) until you set
`hook: not_installed` under `layers:` in `.agents/state.yml`.

### Change a protected path (when `authority` is installed)
`.agents/consequence.yml` lists the consequential paths by category. Claude Code's `Write`, `Edit` and
`NotebookEdit` are denied on `harness` paths unless a `/keel-harness:build` or `/keel-harness:rules`
flow is approved; the other categories ask. Edit the map by hand to add or drop a glob (a person's
editor is never blocked), then `make harness-check`. The hook does not see Bash commands that write
harness paths: `guard` in the gate, pre-commit and CI still catches loosenings.

### Raise the time budget
Edit `.agents/gate.env`. The fast gate should stay fast; prefer moving a slow sensor to
`scripts/sensors/slow/`. A higher budget needs an ADR in the same change that names `.agents/gate.env`.

### Loosen the harness on purpose
`guard` compares the harness with the commit the branch started from (`KEEL_GUARD_BASE`, else the
merge-base with `origin/HEAD`, else `HEAD`). To loosen a baseline, a limit, a list, a budget or a
sensor deliberately, add an ADR in the same change that names each file by path and says why; then
`make gate-fast` passes. Without it, undo the loosening and fix the code.

## Commands

- `make gate-fast`: the fast sensors. Read line 1 of each, fix every `fail` top to bottom.
- `make gate-slow`: mutation testing and diff coverage. Run it before opening a pull request.
- `make harness-check`: validates this harness.
