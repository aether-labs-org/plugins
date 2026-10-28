# keel-harness v0.3 Implementation Plan

**Goal:** Take keel-harness from v0.2.0 to v0.3 as specified in
`docs/specs/2026-10-23-keel-harness-v0.3-design.md`:
- fix the v0.2 defects;
- measure the current plugin;
- refactor it into the v0.3 layout, with flows enforced in code;
- close the criterion's gaps profile by profile;
- release v0.3.0.

**Spec:** read `docs/specs/2026-10-23-keel-harness-v0.3-design.md` before any phase. Each phase cites the
spec section it implements.

## Status

Last reviewed **2026-10-28**, on `claude/harness-engineering-autonomous-agents-d8xhvx`, after F2b and E1
were merged. Suite at that point: `./tests/run.sh` gives **1031** `ok`, and `make validate` passes for
the three plugins.

| Phase | Status | Executable plan | Evidence | Next action |
| --- | --- | --- | --- | --- |
| F0 Fixes | ✅ done 2026-10-24 | `2026-10-24-…-f0-plan.md` | `cf495ff`; 991 `ok`; CI green; the D-1 reproduction fails on `guard` | — |
| F1 Measure | ◐ closed partial 2026-10-28 | `2026-10-24-…-f1-plan.md`, `2026-10-28-…-f1b-plan.md` | 5 read-only cases at `cf495ff` (USD 5.18); F1b stopped at its smoke run (USD 0.22); the 10 tool cases are **not measured** (D49) | — |
| E1 Doctor evals | ✅ done 2026-10-28 | `2026-10-28-…-e1-plan.md` | `c8b71ca`, `823458f`; `doctor-validator-drift` Δ +0.13; `writes-nothing` confounded | E2 |
| E2 Eval graders | ☐ next | to write | — | fix `writes-nothing`; declare tool needs |
| F2a Layout | ✅ done 2026-10-24 | `2026-10-24-…-f2a-plan.md` | `13af4a2`; 1020 `ok`; 56 files, as planned | — |
| F2b State + ADR folder | ✅ done 2026-10-28 | `2026-10-28-…-f2b-plan.md` | `6d16fe3`; 1028 `ok` (1031 with E1) | — |
| F2c Skills and flow | ☐ next, after E2 | to write | — | decide first whether `doctor` stays a skill (§F2c) |
| F2d Assess and context | ☐ | — | — | after F2c |
| F3a CI + pre-commit | ☐ can start now | to write | — | independent of F2c |
| F3b Versioned plans | ☐ | — | — | after F2c (`scripts/keel verify`) |
| F3c Authority | ☐ | — | — | after F3a |
| F3d Exemplars + catalog | ☐ | — | — | after F2c |
| F4 Codex | backlog (D5) | — | — | — |
| F5 Profile L | ☐ | — | — | after F3 |
| F6 Feedback → infrastructure | ☐ | — | — | after F2c |
| R Release v0.3.0 | ☐ | to write | — | last |
| CLI (`feat/keel-cli`) | ❄ frozen, outside v0.3 | `docs/keel-cli-plan` branch | 7 commits on an old base, not reviewed | revisit after R, or when a D48 trigger occurs |

Legend: ✅ done · ◐ done with a documented gap · ☐ not started · ❄ frozen.

**Order from here:** E2 → F2c → F2d; F3a any time; F3b, F3d and F6 after F2c; F3c after F3a; F5 after F3; R last.

## Global constraints

- Everything installed in a target repository stays plain bash 3.2, with no `jq`, no network and no
  model call, and runs with the plugin absent (v0.2 D26, sensor contract §6).
- Installed paths (`scripts/gate.sh`, `scripts/sensors/`, committed `.agents/` files) do not move.
  F2b moved v0.2's ephemeral files into `.agents/run/` (D39), and a v0.2 install upgrades in place
  under confirmation.
- keel never writes `.agents/skills/` or `.agents/plugins/` (D39).
- **Git:**
  - commit once per task and push to the working branch after each commit;
  - never open a pull request without the owner's explicit approval;
  - each phase works on its own `feat/keel-harness-v0.3-<phase>` branch, which is merged into this
    branch once validated.
- **Execution:** each phase gets its own executable plan, written once the previous phase is done and
  validated. Content is prototyped and run before it goes into a plan.
- `make check` and `make validate` stay green after every task.
- **Evals (D49):** only the read-only cases are run (`assess-*`, `doctor-*`, `should-not-trigger`).
  Where an acceptance criterion below needed a tool case, it is met by deterministic tests instead,
  and says so.

## Summary

| Phase | Deliverables | Impact | Effort | Depends on | Risk | Acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| **F0** ✅ | D-1 `guard`; D-2 parser; D-3; D-4; D-5 | High | S | — | Low | D-1 reproduction fails without an ADR naming the file; no `eval` of config; 991 `ok` |
| **F1** ◐ | Baseline of the eval suite at `cf495ff` | High | M ($) | F0 | Medium (host) | Read-only cases recorded with Δ and cost; tool cases not measured (D49) |
| **E1** ✅ | `doctor-*` grant Bash; `doctor-validator-drift` | Medium | S | F1 | Low | Both cases measured; 1023 `ok` |
| **E2** | `writes-nothing` → `tool_used` graders; tool needs declared in every case | Medium | S | E1 | Low | No grader counts harness artifacts; `doctor-*` re-measured (≤ USD 8) |
| **F2a** ✅ | v0.3 layout, `${CLAUDE_PLUGIN_ROOT}` paths | High | M | F0 | Medium | 1020 `ok`; layout test |
| **F2b** ✅ | `.agents/run/`, `adr_dir`, schema 3, v0.2 upgrade | High | M | F2a | Medium | 1028 `ok`; end-to-end run-state check |
| **F2c** | `scripts/keel` phases; skill template; `contracts/`; `disallowed-tools`; size test; traceability; pressure tests | High | L | E2 | Medium | Ported tests green; read-only evals not worse than E1/E2; traceability 100 % |
| **F2d** | `assess` dimensions; LSP; codemap check; triggering evals | Medium | M | F2c | Low | Tests for each new signal; triggering evals pass |
| **F3a** | CI workflow + pre-commit assets | High | S | F2b | Low | A planted defect is red in pre-commit and in CI |
| **F3b** | Versioned plans, lifecycle, progress file, spec traceability | Medium | S | F2c | Low | `keel verify` rejects a plan without Acceptance; a `done` plan is removed |
| **F3c** | Consequence map, deny rules, `claude-protect.sh`, CODEOWNERS, `mandatory` | High | M | F3a | Medium | Hook tests: editing a baseline is denied; `mandatory` cannot be loosened (D49: tests, not evals) |
| **F3d** | Exemplars; D44 catalog; pattern sensor | Medium | L | F2c | Medium | Each entry has sensor tests; **no ablation evidence** (D49), so each entry is marked *unproven* in the catalog |
| **F4** | Codex adapter | Medium | M | F2 | Medium | backlog |
| **F5** | C3 reviewer; C8 journey sensor; C10 documented | Medium | L | F3 | High | Sensor tests; read-only ablation where possible; otherwise *unproven* |
| **F6** | History, lessons inbox, auto-memory coherence, adherence diagnosis | Medium | M | F2c | Low | Fixture tests for each `doctor` report |
| **R** | v0.3.0 release | High | S | all above | Low | Version 0.3.0; spec status; README; tests updated; `make validate` |

---

## F0 — Fixes (spec §6, D32, D33) ✅

Executable plan: `docs/plans/2026-10-24-keel-harness-v0.3-f0-plan.md`.

- [x] **D-5:** `shellcheck` skipped locally when missing, required in CI.
- [x] **D-2:** `lib/envparse.sh`; the nine `eval` calls replaced; `rule-env.md` updated.
- [x] **D-1:** `sensors/common/guard.sh` (D32) installed by `build`; `harness-check` warns `guard-missing`;
  the reproduction is `tests/keel_guard_test.sh`.
- [x] **D-3, D-4:** documentation fixes.
- [x] Regression found later: `measure.sh language` lost the envparse library; fixed in F2a Task 1.

## F1 — Measure the current plugin (spec §2.2 C9, D31) ◐

Plans: `docs/plans/2026-10-24-keel-harness-v0.3-f1-plan.md` (owner's machine) and
`docs/plans/2026-10-28-keel-harness-v0.3-f1b-plan.md` (cloud).

- [x] The 5 read-only cases were measured at `cf495ff`, with Δ and cost (README, "partial baseline").
- [x] F1b attempted the 10 tool cases in a cloud container. Running there as root, the Bash sandbox
  mounted the workspace read-only (README, "F1b attempt").
- [x] **Closed by owner decision (D49, 2026-10-28):** the 10 tool cases are not measured. The
  `rules-effect` comparison, the only test of whether approved rules help an agent, therefore has no
  data.

## E1 — Doctor evals ✅

Plan: `docs/plans/2026-10-28-keel-harness-v0.3-e1-plan.md`.

- [x] Both `doctor-*` cases grant Bash.
- [x] `doctor-validator-drift` replaced `doctor-agents-not-loaded` (README, "E1 results").

## E2 — Eval graders (next)

- [ ] Replace each `writes-nothing` grader (`file_exists **/*`) with `tool_used` graders: `Write`, `Edit`
  and `NotebookEdit` with `min: 0` and `max: 0`, plus `Bash` whose input matches a write
  (`>`, `tee`, `rm`, `mv`, `sed -i`, `git add|commit`) with `max: 0`. Claude Code's Bash tool creates
  `.claude/.cc-writes/`, which `file_exists` counts (E1).
- [ ] Every case declares in `allowed_tools` the tools its prompt needs. For example,
  `gate-catches-defect` asks for `make` and a file but lists `[Read, Glob, Grep]`.
- [ ] Re-measure both `doctor-*` cases, with an approved ceiling (≤ USD 8).

## F2 — Refactor (spec §4, §5, D29, D34–D38)

### F2a — layout ✅

Plan: `docs/plans/2026-10-24-keel-harness-v0.3-f2a-plan.md`.

- [x] `assets/core/`, `assets/adapters/claude/` and `scripts/`, moved with `git mv`; `${CLAUDE_PLUGIN_ROOT}`
  paths; `tests/keel_layout_test.sh`.

### F2b — state and ADR folder ✅

Plan: `docs/plans/2026-10-28-keel-harness-v0.3-f2b-plan.md`.

- [x] Run state in `.agents/run/`, with the `run-state` check (D39).
- [x] `adr_dir:` in `state.yml`, detected or `docs/adr/` (D45); `guard` and the sensor guidance use it.
- [x] `schema_version: 3` and the v0.2 upgrade round in `build` §7b.

### F2c — skills and flow

- [ ] **Decision first: does `doctor` stay a skill?**
  - E1 measured little added value: `doctor-finds-drift` Δ −0.22 once Bash was granted, and
    `doctor-validator-drift` Δ +0.13.
  - Options: keep it; fold it into `assess`; or reduce it to "run the plugin's validator, compare it
    with the installed copy, and explain".
  - The owner decides, with E2's numbers.
- [ ] `scripts/keel` with `plan | approve | apply | verify | measure | check`; approvals in
  `.agents/run/flow/`; `apply` refuses without an approval matching the proposal hash.
- [ ] `contracts/` (`sensor.md`, `rule-env.md`, `state.md`, `flow.md`, `plan.md`), moved from the skills'
  references.
- [ ] `contracts/rule-env.md` gains `ENFORCEMENT_LEVEL=mandatory|ratchet` (default `ratchet`).
  `harness-check` warns on a `mandatory` rule without a computational sensor. `AGENTS.md` lists the
  `mandatory` rules first. `rules` reads `.specify/memory/constitution.md` when it is present.
- [ ] Rewrite each SKILL.md on the template in spec §5.5, one skill at a time: **doctor (or its
  replacement), then assess, then build, then rules**. Each prose self-verify list moves into
  `keel verify <skill>`.
- [ ] `disallowed-tools: Write Edit NotebookEdit` on `assess` and `doctor`.
- [ ] `tests/keel_skill_size_test.sh`: every SKILL.md under 20,000 bytes.
- [ ] Traceability matrix (`contracts/flow.md`): every `never`/`always` in a skill maps to a test, a
  `keel verify` item or an eval grader, classified by form (recipe / slot / discipline).
- [ ] Pressure tests for the discipline rules.
  - `assess` and `doctor` are read-only, so with/without evals can test them.
  - For `build` and `rules`, "write nothing before the user accepts" is enforced by `keel apply` and
    covered by its tests (D49).
- [ ] Acceptance:
  - ported tests green;
  - read-only evals not worse than E2;
  - `validate --strict` ok;
  - a v0.2 repository upgrades through `build` with a green gate.

### F2d — assess and context

- [ ] `assess` gains flakiness (run the suite N times), build reproducibility, headless setup and
  observability signals, each with evidence and cost, still with no aggregate score.
- [ ] `build` proposes the stack's official LSP plugin. `rules` writes the codemap into
  `docs/architecture.md`, and `harness-check` warns `codemap-stale` on cited paths that no longer exist.
- [ ] Triggering evals for each skill, should and should not trigger. They are read-only, so they run.

## F3a — CI and pre-commit (D7 revised)

- [ ] `assets/core/ci/keel.yml`: on pull request, `make gate-fast`, `make harness-check`, and `guard`
  over the PR diff (`KEEL_GUARD_BASE` set to the target branch); `gate-slow` behind an opt-in input.
- [ ] `assets/core/precommit/`: lefthook, pre-commit and husky variants; `build` proposes the one the
  repository already uses, or none.
- [ ] `harness-check.sh` warns when local and CI commands diverge.

## F3b — Versioned plans and progress (D6 revised, D40)

- [ ] Plan template with a required **Acceptance** section in the sensors' numbers (spec-anchored,
  kept small). `.agents/plans/` stops being git-ignored.
- [ ] Lifecycle `active | done | abandoned` in each plan's header. `keel` removes a `done` plan after
  its ADR or commit is referenced. `harness-check` warns `plan-stale` (active and untouched for 30
  days, adjustable) and `progress-size` (over 200 lines, adjustable).
- [ ] `.agents/progress.md`, pointed at by `AGENTS.md`; `keel verify` rejects a plan without Acceptance.
- [ ] Spec traceability (D46): specs are read from `docs/specs/` or an existing Spec Kit layout, and
  `harness-check` warns `acceptance-untested` when an acceptance criterion names no test.

## F3c — Authority (C7 + R)

- [ ] `contracts/consequence.md` and a generated `.agents/consequence.yml` (paths × category: auth,
  data, infra, public contract, harness).
- [ ] From it:
  - deny rules merged into `.claude/settings.json`;
  - `assets/adapters/claude/claude-protect.sh` (PreToolUse), which denies edits to `harness` paths
    and names the approved route in the reason;
  - CODEOWNERS entries for consequential paths.
- [ ] `mandatory` rules (D43):
  - `guard` rejects loosening even when an added ADR names the file;
  - their env files and exception lists are protected paths;
  - their sensors are a required CI check;
  - an amendment is a superseding ADR approved through CODEOWNERS.
- [ ] Sandbox / devcontainer as an option for profile L, with the trade-off stated.
- [ ] Hook and `guard` tests show that editing a baseline is denied and that a `mandatory` rule
  cannot be loosened. Tests, not evals (D49).

## F3d — Exemplars and catalog

- [ ] `EXEMPLAR=` in rule env files, a "follow X, not Y" line in nested `AGENTS.md`, legacy zones
  marked.
- [ ] Catalog entries: function length, cyclomatic complexity, max parameters, optional dead code /
  duplication, and the ten D44 entries: `comments`, `spelling`, `code-style`, `naming`,
  `suppressions`, `dependencies`, `type-strictness`, `error-handling`, `logging`, `test-conventions`.
  Each comes with sensor tests.
- [ ] A generic `pattern` sensor (ast-grep / semgrep / grep) for a team's own approved rules.
- [ ] `rules` proposes an entry only when `measure.sh` shows a problem or the user asks for it.
- [ ] Each entry is marked **unproven** in `catalog.md` until a with/without measurement exists (D49).

## F4 — Codex adapter (backlog, D5)

- [ ] `.codex-plugin/plugin.json` beside the existing manifest, one shared `skills/`.
- [ ] `assets/adapters/codex/` running the fast gate from a Codex Stop hook (`hooks.json`).

## F5 — Profile L

- [ ] C3: an optional reviewer sensor that calls a different model, with a token budget and a
  calibration fixture; never in the fast gate.
- [ ] C8: a journey sensor (Playwright) for web stacks, plus structured-log guidance.
- [ ] C10: documentation only. The D47 recipe goes in `.agents/README.md` and the plugin README.
- [ ] Each component has tests; where no read-only ablation applies, it is marked **unproven** (D49).

## F6 — Feedback into infrastructure

- [ ] Each gate run's per-sensor status goes to `.agents/run/history/`, keeping the last 50 runs
  (adjustable). The validator (or `doctor`) reports sensors that are always green or always red.
- [ ] Lessons inbox `.agents/run/learnings/`, with promotion proposals written only with approval.
- [ ] Auto-memory coherence report; never edits memory.
- [ ] Transcript adherence diagnosis (did the flow's phases happen, in order).
- [ ] Recurring failures grouped by class, with the guide or sensor that would have prevented them.
- [ ] On a model change, re-run the read-only evals and move `harness_review_by`.

## R — Release v0.3.0

- [ ] `plugin.json` version `0.3.0`. `tests/structure_test.sh` checks `0.3.0` and the v0.3 spec status
  `implemented in v0.3.0`. The v0.2 spec keeps its own status.
- [ ] README: the skills section, the v0.3 eval table (read-only cases), and the D49 note on the
  unmeasured tool cases.
- [ ] Marketplace description, if it changed.
- [ ] `make check` and `make validate` green; a pull request to `main` opened only with the owner's
  approval.
