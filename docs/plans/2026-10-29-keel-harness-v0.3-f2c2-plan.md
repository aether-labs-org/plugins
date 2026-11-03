# keel-harness v0.3 — F2c-2 `scripts/keel`: the flow in code: Implementation Plan

> **For agentic workers:** read `docs/plans/2026-10-29-keel-harness-v0.3-agent-rules.md` first. Phase id: `f2c2`. Free; no eval. Starts after F2c-1 and H1 are merged.

**Goal:** Spec §5.1: the order of a skill's phases is enforced by code, not prose. `scripts/keel` (D34: no `bin/`; skills call `${CLAUDE_PLUGIN_ROOT}/scripts/keel`) records a proposal, the user's approval of exactly that proposal, and the self-verification. `build`, `rules` and `assess` call it. F2c-3 then rewrites those skills on the §5.5 template; here you only wire the calls.

## The CLI (bash 3.2, no `jq`, no network; runs from the target repository root)

State lives in `.agents/run/flow/` (git-ignored). Hashes are `git hash-object <file>`: portable, and the repository is a git repo by precondition.

| Command | Behaviour | Exit |
| --- | --- | --- |
| `keel check pre <skill>` | Preconditions (table below). For `assess`, also snapshots `git status --porcelain` (minus `.agents/run/`) into `.agents/run/flow/assess.pre` | 0 met; 1 unmet, with one `missing: …` line per item |
| `keel plan <skill> <file>` | Copies `<file>` to `.agents/run/flow/<skill>.proposal`, deletes any `<skill>.approved` / `.applied`, prints `proposal <skill> <hash>` | 0; 1 if `<file>` is missing |
| `keel approve <skill> <hash>` | Writes `<skill>.approved` as `<hash><TAB><UTC ISO time>`. Run only after the user accepted the proposal in conversation | 0; 1 with no proposal or a hash that is not the current proposal's |
| `keel apply <skill>` | The gate before any write: checks that `<skill>.approved` names the current proposal's hash, then writes `<skill>.applied` (time) | 0 approved; 1 with `no approval for the current proposal - show it to the user, then run keel approve` |
| `keel verify <skill>` | The self-verification (tables below). One line per item: `ok <item>` or `fail <item>: <why>` | 0 all ok; 1 any fail |
| `keel measure …` / `keel render …` | `exec` the existing `scripts/measure.sh` / `scripts/render.sh` with the same arguments | theirs |
| `keel check` (no skill) | Runs the plugin's `assets/core/harness-check.sh` in the repository | its exit code |
| anything else | usage on stderr | 64 |

`<skill>` is one of `assess build rules`; any other name exits 64.

**Preconditions (`check pre`):**
- `build`: inside a git work tree.
- `rules`: `scripts/gate.sh`, `scripts/lib/baseline.sh`, `scripts/lib/envparse.sh`, `scripts/sensors/guard.sh`, `.agents/state.yml`, and the Makefile targets `gate-fast` and `gate-slow`. This is today's `rules` §0.
- `assess`: inside a git work tree.

**`verify build`** (today's `build/SKILL.md` §10, made computable):
1. `AGENTS.md` exists, has ≤ 100 lines, has no `{{`, and has a `Last updated: YYYY-MM-DD` line.
2. `.agents/state.yml` has `schema_version: 3`, and `git check-ignore -q .agents/run/x` succeeds.
3. `.agents/run/last-run.log` exists, and its last line starts with `gate: fast - ` (the gate ran).
4. `bash scripts/harness-check.sh` exits 0.
5. Every `.agents/baselines/*.tsv` starts with `# measured_at:`.
6. Neither `scripts/gate.sh` nor anything under `scripts/sensors/` or `scripts/lib/` contains `${CLAUDE_` or `claude ` as a command. `scripts/sensors/guard.sh` and `scripts/lib/envparse.sh` exist.
7. When `state.yml` says `hook: installed`:
   - `.claude/settings.json` has a `Stop` entry naming `scripts/hooks/claude-stop.sh` and the literal `${CLAUDE_PROJECT_DIR}`, and no `PostToolUse` entry running `gate`;
   - the hook script is executable;
   - JSON validity is checked with `python3 -m json.tool` when `python3` exists; otherwise the item says `skip (no python3)`, which counts as ok.
8. `.agents/run/flow/build.applied` exists (the install went through `keel apply`).

**`verify rules`** (today's "Done when", made computable):
1. `bash scripts/harness-check.sh` exits 0.
2. `.agents/run/last-run.log` ends with `gate: fast - PASSED`.
3. Every `.agents/rules/*.env` parses with `scripts/lib/envparse.sh` and has `RULE_ID`, `KIND`, `ORIGIN` and `DOC`.
4. Every `DOC=<file>#<anchor>` resolves to an `<a id="<anchor>">` in that file.
5. `.agents/run/flow/rules.applied` exists.

**`verify assess`:** `git status --porcelain` minus `.agents/run/` equals the `assess.pre` snapshot. Without a snapshot, fail with `run keel check pre assess first`.

## Tasks

- [ ] **Task 1 — tests first:** `tests/keel_cli_test.sh` covers every row of the CLI table and every verify item, pass and fail. Build fixture repositories with the existing helpers. For `verify build`, start from a clean installed fixture; `tests/keel_harness_check_test.sh` `mkclean` is a good model. Add a `.agents/run/last-run.log`, then break one item at a time. Also test that `apply` refuses after `plan` without `approve`, and refuses after the proposal file changed (`plan` again → new hash). The suite must fail before the script exists.
- [ ] **Task 2 — `plugins/keel-harness/scripts/keel`** (executable, `#!/usr/bin/env bash`, `set -uo pipefail`), implementing the table. Write temp files per H1's rule (TMPDIR, else `.agents/run/tmp/`). Run `shellcheck -S warning`. Commit tests and script together: `feat(keel-harness): scripts/keel records proposal, approval and verification (spec §5.1)`.
- [ ] **Task 3 — `contracts/flow.md`.** Fill its `## Phases` section: the CLI table, the state files, and the rule "no write before `keel apply` exits 0; done means `keel verify` exits 0". Leave `## Traceability` for F2c-3. Commit `docs(keel-harness): contracts/flow.md phases`.
- [ ] **Task 4 — wire the skills** (minimal edits; F2c-3 rewrites them):
  - **`build`:**
    - start with `keel check pre build`;
    - §8 "Propose, then write": write the proposal to a temp file, run `keel plan build <file>`, show it, and run `keel approve build <hash>` only after the user accepts. Up-front acceptance in the user's request counts, as today; say so in the reply;
    - run `keel apply build` before the first write, and stop if it exits non-zero;
    - replace §10's checklist with "run `keel verify build`; fix every `fail` line and re-run until it exits 0". Keep the two items `keel` cannot check (commands in `AGENTS.md` really run; deep content is pointers) as two short lines.
    - This must bring `build/SKILL.md` well under 250 lines.
  - **`rules`:** the same pattern. `keel check pre rules` replaces §0's prose list; `keel plan`/`approve`/`apply` go around §7; `keel verify rules` replaces "Done when".
  - **`assess`:** `keel check pre assess` first, and `keel verify assess` last.

  Update the tests that grep the skills' prose (`tests/build_test.sh`, `tests/rules_test.sh`, `tests/assess_test.sh`) where they asserted the removed checklist lines. Each assertion must still check the same intent, now as a `keel` call. Commit `feat(keel-harness): build, rules and assess run through scripts/keel`.
- [ ] **Task 5 — README and master plan.**
  - The README gets a short "How the flow is enforced" paragraph.
  - The master plan's F2c item for `scripts/keel` is ticked.
  - Commit `docs(keel-harness): F2c-2 done`.

## Acceptance

- `tests/keel_cli_test.sh` is green and was red before Task 2.
- In a fixture: `keel plan` → `keel apply` exits 1; `keel approve <hash>` → `keel apply` exits 0; editing the proposal and running `keel plan` again → `keel apply` exits 1.
- `keel verify build` exits 0 on the clean fixture and 1 for each broken item, naming it.
- No SKILL.md keeps a prose checklist that duplicates a `keel verify` item.
- `./tests/run.sh` exits 0; `validate --strict` passes; `shellcheck` is clean; no `bin/` directory.
- Known limit (write it in `contracts/flow.md`): the agent itself runs `keel approve`. The hash proves that what was approved is what gets applied, not that a human said yes. F3c's PreToolUse hook and the process evals (spec §5.4) are the other layers.
