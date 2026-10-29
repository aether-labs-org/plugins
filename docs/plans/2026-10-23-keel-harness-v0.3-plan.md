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
the three plugins. The same day, a round of questions with the owner reversed D49 (D50: the tool cases
run on the owner's machine), folded `doctor` into `assess` (D51), and tied profile L to evidence (D52).

| Phase | Status | Executable plan | Evidence | Next action |
| --- | --- | --- | --- | --- |
| F0 Fixes | ✅ done 2026-10-24 | `2026-10-24-…-f0-plan.md` | `cf495ff`; 991 `ok`; CI green; the D-1 reproduction fails on `guard` | — |
| F1 Measure | ◐ closed partial 2026-10-28 | `2026-10-24-…-f1-plan.md`, `2026-10-28-…-f1b-plan.md` | 5 read-only cases at `cf495ff` (USD 5.18); F1b stopped at its smoke run (USD 0.22); the 10 tool cases move to E3 (D50) | — |
| E1 Doctor evals | ✅ done 2026-10-28 | `2026-10-28-…-e1-plan.md` | `c8b71ca`, `823458f`; `doctor-validator-drift` Δ +0.13; `writes-nothing` confounded | E2 |
| E2 Eval graders | ✅ done 2026-10-29 | `2026-10-28-…-e2-plan.md` | `0c6e040`, `bb5c87d`; 1053 `ok` (no shellcheck); USD 2.91 of 6; `doctor-*` Δ +0.17 / +0.28; `no-bash-write` flags `mkdir` of `TMPDIR` | E3, F2c |
| H1 Temp-dir hardening | ☐ **next**, before E3 | to write | found validating E2 (below) | owner's call |
| E3 Tool cases | ☐ after E2 (merged) and H1 | `2026-10-28-…-e3-plan.md` | not run yet: no `feat/keel-harness-v0.3-e3` branch on 2026-10-29 | owner's machine; AppArmor profile for `bwrap`, removed after (D50) |
| F2a Layout | ✅ done 2026-10-24 | `2026-10-24-…-f2a-plan.md` | `13af4a2`; 1020 `ok`; 56 files, as planned | — |
| F2b State + ADR folder | ✅ done 2026-10-28 | `2026-10-28-…-f2b-plan.md` | `6d16fe3`; 1028 `ok` (1031 with E1) | — |
| F2c Skills and flow | ◐ F2c-1 done 2026-10-29 | `2026-10-29-…-f2c1-plan.md` | `646d5ae`, `dc95a1b`, `cfa7a77`; 1156 `ok` (1085 before); `validate --strict` passes; owner's paid run of `assess-*-drift` and `assess-*` still open (D51) | F2c-2 (`scripts/keel`), F2c-3 (skill template, traceability) |
| F2d Assess and context | ☐ | — | — | after F2c |
| F3a CI + pre-commit | ◐ done 2026-10-28, gap: workflow not run on GitHub | `2026-10-28-…-f3a-plan.md` | `9e5d26f`, `13abe5a`; 1063 `ok` (1112 with E2); `claude plugin validate --strict` passes; Task 4 skipped by the owner: `github.base_ref` and `fetch-depth: 0` unproven on GitHub | F3c |
| F3b Versioned plans | ☐ | — | — | after F2c (`scripts/keel verify`) |
| F3c Authority | ☐ | — | — | after F3a |
| F3d Exemplars + catalog | ☐ | — | — | after F2c |
| F4 Codex | backlog (D5) | — | — | — |
| F5 Profile L | ☐ | — | — | after F3; ships only with Δ > 0 per component, else v0.4 (D52) |
| F6 Feedback → infrastructure | ☐ | — | — | after F2c |
| R Release v0.3.0 | ☐ | to write | — | last |
| CLI (`feat/keel-cli`) | ❄ frozen, outside v0.3 | `docs/keel-cli-plan` branch | 7 commits on an old base, not reviewed | revisit after R, or when a D48 trigger occurs |

Legend: ✅ done · ◐ done with a documented gap · ☐ not started · ❄ frozen.

**Validated 2026-10-29.**
- **E2 and F3a:**
  - both match their prototypes byte for byte;
  - suites: 1080 / 1063 `ok` apart, **1112** merged into this branch;
  - E2's README numbers match its JSON files (USD 2.91).
- **Finding (H1).** `harness-check.sh`, `guard.sh` and nine more installed scripts call `mktemp`
  without checking that it worked. With no usable `TMPDIR`, which E2's eval sandbox did not have:
  - `tmp` is empty, and the scripts write `/sizes`, `/stale`, `/loose` and similar at the
    filesystem root. As root that succeeds; otherwise the writes fail;
  - `guard` then fails on every run, with a malformed summary (` loosening(s)` with no count);
  - the agent works around it with `mkdir` of its own `TMPDIR`. That is the false positive E2
    recorded for `no-bash-write`; it is not a grader bug.
- **H1 proposal:**
  - each script falls back to `.agents/run/tmp/` (ignored, inside the workspace) and fails with a
    clear message if that fails too;
  - tests run every script with an unusable `TMPDIR`;
  - H1 runs before E3, because E3's `tools` cases run these sensors inside the same sandbox.

**Order from here:** E2 and F3a in parallel → E3 (owner's machine) and F2c → F2d; F3b, F3d and F6 after F2c; F3c after F3a; F5 after F3; R last. E3 can run beside F2c, but F2c's acceptance for `build` and `rules` waits for E3's numbers.

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
- **Evals (D50):** cases run by grant group (`--tag readonly | bash | tools | effect`, README). The
  read-only groups run in a cloud session; `tools` and `effect` run on the owner's machine (E3).
  Until E3 reports, an acceptance criterion that needs a tool case is met by deterministic tests and
  the item is marked *unproven*; E3's numbers then become the ruler.

## Summary

| Phase | Deliverables | Impact | Effort | Depends on | Risk | Acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| **F0** ✅ | D-1 `guard`; D-2 parser; D-3; D-4; D-5 | High | S | — | Low | D-1 reproduction fails without an ADR naming the file; no `eval` of config; 991 `ok` |
| **F1** ◐ | Baseline of the eval suite at `cf495ff` | High | M ($) | F0 | Medium (host) | Read-only cases recorded with Δ and cost; tool cases moved to E3 (D50) |
| **E1** ✅ | `doctor-*` grant Bash; `doctor-validator-drift` | Medium | S | F1 | Low | Both cases measured; 1023 `ok` |
| **E2** | `tool_used` write graders; tool lists; grant-group tags; `should-not-trigger` covers `rules` | Medium | S | E1 | Low | No `file_exists **/*` grader; every case in one group; read-only and `bash` groups re-measured (≤ USD 6) |
| **E3** | The 10 tool cases measured on the owner's machine | High | M ($) | E2 | Medium (host) | Nested-sandbox check passes; every tool case recorded with Δ and cost; `rules-effect` compared; AppArmor profile removed |
| **F2a** ✅ | v0.3 layout, `${CLAUDE_PLUGIN_ROOT}` paths | High | M | F0 | Medium | 1020 `ok`; layout test |
| **F2b** ✅ | `.agents/run/`, `adr_dir`, schema 3, v0.2 upgrade | High | M | F2a | Medium | 1028 `ok`; end-to-end run-state check |
| **F2c** | `doctor` folded into `assess` (D51); `scripts/keel` phases; skill template; `contracts/`; `disallowed-tools`; size test; traceability; pressure tests | High | L | E2 (E3 for `build`/`rules` acceptance) | Medium | Ported tests green; merged `assess` not worse than E2 on `doctor-*` and F1 on `assess-*`; `build`/`rules` not worse than E3; traceability 100 % |
| **F2d** | `assess` dimensions; LSP; codemap check; triggering evals | Medium | M | F2c | Low | Tests for each new signal; triggering evals pass |
| **F3a** | CI workflow + pre-commit assets | High | S | F2b | Low | A planted defect is red in pre-commit and in CI |
| **F3b** | Versioned plans, lifecycle, progress file, spec traceability | Medium | S | F2c | Low | `keel verify` rejects a plan without Acceptance; a `done` plan is removed |
| **F3c** | Consequence map, deny rules, `claude-protect.sh`, CODEOWNERS, `mandatory` | High | M | F3a | Medium | Hook tests: editing a baseline is denied; `mandatory` cannot be loosened |
| **F3d** | Exemplars; D44 catalog; pattern sensor | Medium | L | F2c | Medium | Each entry has sensor tests and a with/without run as in E3 (D44); an entry without one is marked *unproven* in the catalog |
| **F4** | Codex adapter | Medium | M | F2 | Medium | backlog |
| **F5** | C3 reviewer; C8 journey sensor; C10 documented | Medium | L | F3 | High | Sensor tests; Δ > 0 per component, or it moves to v0.4 (D52) |
| **F6** | History, lessons inbox, auto-memory coherence, adherence diagnosis | Medium | M | F2c | Low | Fixture tests for each `assess` report |
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
- [x] **Closed by owner decision (D49, 2026-10-28):** the 10 tool cases were left unmeasured.
- [x] **Reversed the same day (D50):** they move to E3, on the owner's machine.

## E1 — Doctor evals ✅

Plan: `docs/plans/2026-10-28-keel-harness-v0.3-e1-plan.md`.

- [x] Both `doctor-*` cases grant Bash.
- [x] `doctor-validator-drift` replaced `doctor-agents-not-loaded` (README, "E1 results").

## E2 — Eval graders (next)

Plan: `docs/plans/2026-10-28-keel-harness-v0.3-e2-plan.md`.

- [ ] Each "writes nothing" grader (`file_exists **/*`) becomes four `tool_used` graders, weight 0.25
  each: `Write`, `Edit` and `NotebookEdit` with `max: 0`, plus `Bash` whose input matches a write
  command. Claude Code's Bash tool creates `.claude/.cc-writes/`, which `file_exists` counts (E1).
- [ ] Every case lists in `allowed_tools` the tools its prompt needs. `allowed_tools` grants only
  read-only tools; gated ones come from `--allow-tools`, and a missing grant shows as `not granted`.
- [ ] Every case gets one grant-group tag: `readonly`, `bash`, `tools` or `effect`.
- [ ] `should-not-trigger` also checks the `rules` skill.
- [ ] Re-measure the `readonly` and `bash` groups, with an approved ceiling (≤ USD 6).

## E3 — Tool cases on the owner's machine (D50)

Plan: `docs/plans/2026-10-28-keel-harness-v0.3-e3-plan.md`.

- [ ] A temporary AppArmor profile lets only `/usr/bin/bwrap` create user namespaces. It is checked
  before any paid run and removed after.
- [ ] The `tools` group (8 cases) runs with/without; the `effect` pair runs with `--ablation none`,
  and the two are compared.
- [ ] Results go to the README and `docs/evals/keel-v0.3-e3/`. They become the ruler for `build`
  and `rules` in F2c, and the starting point for F3d's catalog ablations.

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

- [x] **Fold `doctor` into `assess` (D51, decided 2026-10-28).** Done in F2c-1; the paid with/without run of the merged `assess` is open (owner).
  - With an installed harness, `assess` runs the plugin's own `harness-check.sh`, compares it with
    the repository's copy and explains each warning.
  - The validator and its tests stay unchanged.
  - The `doctor-*` eval cases move to `assess`.
  - The README names the removed `/keel-harness:doctor` as a breaking change.
- [ ] `scripts/keel` with `plan | approve | apply | verify | measure | check`; approvals in
  `.agents/run/flow/`; `apply` refuses without an approval matching the proposal hash.
- [x] `contracts/` (`sensor.md`, `rule-env.md`, `state.md`, `flow.md`, `plan.md`), moved from the skills'
  references. Done in F2c-1; `flow.md` is a stub until F2c-2 (Phases) and F2c-3 (Traceability).
- [ ] `contracts/rule-env.md` gains `ENFORCEMENT_LEVEL=mandatory|ratchet` (default `ratchet`).
  `harness-check` warns on a `mandatory` rule without a computational sensor. `AGENTS.md` lists the
  `mandatory` rules first. `rules` reads `.specify/memory/constitution.md` when it is present.
- [ ] Rewrite each SKILL.md on the template in spec §5.5, one skill at a time: **assess (with
  doctor folded in), then build, then rules**. Each prose self-verify list moves into
  `keel verify <skill>`.
- [x] `disallowed-tools: Write Edit NotebookEdit` on `assess`.
- [x] `tests/keel_skill_size_test.sh`: every SKILL.md under 20,000 bytes.
- [ ] Traceability matrix (`contracts/flow.md`): every `never`/`always` in a skill maps to a test, a
  `keel verify` item or an eval grader, classified by form (recipe / slot / discipline).
- [ ] Pressure tests for the discipline rules.
  - `assess` is read-only, so with/without evals in a cloud session can test it.
  - For `build` and `rules`, "write nothing before the user accepts" is enforced by `keel apply` and
    covered by its tests; the `tools` group (E3) measures the effect.
- [ ] Acceptance:
  - ported tests green;
  - merged `assess` not worse than E2 on `doctor-*` and F1 on `assess-*`;
  - `build-*` and `rules-*` not worse than E3 (re-run on the owner's machine);
  - `validate --strict` ok;
  - a v0.2 repository upgrades through `build` with a green gate.

### F2d — assess and context

- [ ] `assess` gains flakiness (run the suite N times), build reproducibility, headless setup and
  observability signals, each with evidence and cost, still with no aggregate score.
- [ ] `build` proposes the stack's official LSP plugin. `rules` writes the codemap into
  `docs/architecture.md`, and `harness-check` warns `codemap-stale` on cited paths that no longer exist.
- [ ] Triggering evals for each skill, should and should not trigger. They are read-only, so they run.

## F3a — CI and pre-commit (D7 revised)

Plan: `docs/plans/2026-10-28-keel-harness-v0.3-f3a-plan.md`.

- [ ] `assets/core/ci/keel.yml`, run on every pull request:
  - `make gate-fast`, with `guard` compared against the target branch (`KEEL_GUARD_BASE`,
    `fetch-depth: 0`);
  - `make harness-check`, advisory only;
  - actions pinned to a commit SHA;
  - no slow gate: its sensors are diff-scoped, and a clean checkout has no diff.
- [ ] `assets/core/precommit/`: lefthook, pre-commit and husky snippets. `build` proposes the one the
  repository already uses, or declines the layer (`references/enforcement.md`).
- [ ] New optional `layers` keys `ci` and `precommit`. `harness-check` warns `enforcement-drift` when
  an installed layer no longer runs the gate.
- [ ] Acceptance: a planted defect is red in a real git pre-commit hook and in the workflow's gate step
  run on a pull request clone; so is a baseline loosened without an ADR. A run on GitHub is the
  owner's call (plan Task 4).

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
  cannot be loosened.

## F3d — Exemplars and catalog

- [ ] `EXEMPLAR=` in rule env files, a "follow X, not Y" line in nested `AGENTS.md`, legacy zones
  marked.
- [ ] Catalog entries: function length, cyclomatic complexity, max parameters, optional dead code /
  duplication, and the ten D44 entries: `comments`, `spelling`, `code-style`, `naming`,
  `suppressions`, `dependencies`, `type-strictness`, `error-handling`, `logging`, `test-conventions`.
  Each comes with sensor tests.
- [ ] A generic `pattern` sensor (ast-grep / semgrep / grep) for a team's own approved rules.
- [ ] `rules` proposes an entry only when `measure.sh` shows a problem or the user asks for it.
- [ ] Each entry gets a with/without run as in E3 (D44); until it has one, it is marked **unproven** in
  `catalog.md`.

## F4 — Codex adapter (backlog, D5)

- [ ] `.codex-plugin/plugin.json` beside the existing manifest, one shared `skills/`.
- [ ] `assets/adapters/codex/` running the fast gate from a Codex Stop hook (`hooks.json`).

## F5 — Profile L

- [ ] C3: an optional reviewer sensor that calls a different model, with a token budget and a
  calibration fixture; never in the fast gate.
- [ ] C8: a journey sensor (Playwright) for web stacks, plus structured-log guidance.
- [ ] C10: documentation only. The D47 recipe goes in `.agents/README.md` and the plugin README.
- [ ] Each component has tests and a with/without measurement with Δ > 0. Without one, it moves to
  v0.4, and the release marks profile L as partial (D52).

## F6 — Feedback into infrastructure

- [ ] Each gate run's per-sensor status goes to `.agents/run/history/`, keeping the last 50 runs
  (adjustable). The validator (through `assess`, D51) reports sensors that are always green or always red.
- [ ] Lessons inbox `.agents/run/learnings/`, with promotion proposals written only with approval.
- [ ] Auto-memory coherence report; never edits memory.
- [ ] Transcript adherence diagnosis (did the flow's phases happen, in order).
- [ ] Recurring failures grouped by class, with the guide or sensor that would have prevented them.
- [ ] On a model change, re-run the read-only evals and move `harness_review_by`.

## R — Release v0.3.0

- [ ] `plugin.json` version `0.3.0`. `tests/structure_test.sh` checks `0.3.0` and the v0.3 spec status
  `implemented in v0.3.0`. The v0.2 spec keeps its own status.
- [ ] README:
  - the skills section without `doctor`;
  - a breaking-change note: `/keel-harness:doctor` is now part of `assess` (D51);
  - the v0.3 eval table with every group (E2 and E3 rulers, the F2c re-run);
  - profile L marked partial if any F5 component moved to v0.4 (D52).
- [ ] Marketplace description, if it changed.
- [ ] `make check` and `make validate` green; a pull request to `main` opened only with the owner's
  approval.
