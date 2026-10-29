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
| H1 Temp-dir hardening | ✅ done 2026-10-29 | `2026-10-29-…-h1-plan.md` | `7dbef9b`; 1264 `ok` (1112 before, 152 new in `keel_tmpdir_test.sh`: 37 `ok` / 115 FAIL on the old code); `validate --strict` and `shellcheck -S warning` clean; all 16 call sites; `exit 3` of `harness-check` goes into `assess` at merge | E3 |
| E3 Tool cases | ☐ after E2 (merged) and H1 | `2026-10-28-…-e3-plan.md` | not run yet: no `feat/keel-harness-v0.3-e3` branch on 2026-10-29 | owner's machine; AppArmor profile for `bwrap`, removed after (D50) |
| F2a Layout | ✅ done 2026-10-24 | `2026-10-24-…-f2a-plan.md` | `13af4a2`; 1020 `ok`; 56 files, as planned | — |
| F2b State + ADR folder | ✅ done 2026-10-28 | `2026-10-28-…-f2b-plan.md` | `6d16fe3`; 1028 `ok` (1031 with E1) | — |
| F2c Skills and flow | ✅ done 2026-10-29 (F2c-1 and F2c-2 merged; F2c-3 on `feat/keel-harness-v0.3-f2c3`); `ENFORCEMENT_LEVEL` moved to F3c; evals not re-run (owner) | `2026-10-29-…-f2c1/f2c2/f2c3-plan.md` | `646d5ae`, `dc95a1b`, `cfa7a77`; F2c-3: 1755 `ok` (1505 before), `validate --strict` passes, 9 traceability rows are written gaps (`none`); owner's paid re-run of `--tag readonly`, `--tag bash` and the new `--tag pressure` still open (D51) | owner: re-run the eval groups |
| F2d Assess and context | ✅ done 2026-10-29; triggering evals not run (owner) | `2026-10-29-…-f2d-plan.md` | `c378144`, `8f6128c`, `0d904a5`, `587f778` on `feat/keel-harness-v0.3-f2d`; 1941 `ok` (1759 before), `validate --strict` passes; 11 rubric axes; LSP names from the official code-intelligence page; `codemap-stale` is check 16; 9 `trigger-*` cases | owner: run `--tag trigger` (read-only) |
| F3a CI + pre-commit | ◐ done 2026-10-28, gap: workflow not run on GitHub | `2026-10-28-…-f3a-plan.md` | `9e5d26f`, `13abe5a`; 1063 `ok` (1112 with E2); `claude plugin validate --strict` passes; Task 4 skipped by the owner: `github.base_ref` and `fetch-depth: 0` unproven on GitHub | F3c |
| F3b Versioned plans | ✅ done 2026-10-29 | `2026-10-29-…-f3b-plan.md` | `a40bbcf`, `cc98527`, `1f18d9a`, `5448cf4`; 1836 `ok` (1759 before), `validate --strict` passes, shellcheck clean; the 3 new checks bring harness-check to 18 | F6 |
| F3c Authority | ◐ F3c-1 done 2026-10-29; F3c-2 wave E | `2026-10-29-…-f3c1/f3c2-plan.md` | F3c-1 on `feat/keel-harness-v0.3-f3c1`: `b7efeef`, `9c496a0`, `a6df5f9`; 1985 `ok` (1759 before, 226 new), 0 FAIL, `validate --strict` and `shellcheck -S warning` clean; no eval run | F3c-2 (`mandatory`, `ENFORCEMENT_LEVEL`) |
| F3d Exemplars + catalog | ◐ F3d-1 done 2026-10-29; F3d-2 wave F | `2026-10-29-…-f3d1/f3d2-plan.md` | F3d-1 on `feat/keel-harness-v0.3-f3d1`: exemplars and `exemplar-missing` (check 21), `pattern.sh` (grep tested fully; ast-grep and semgrep skip when absent, parsing tested with stubs, never run against the real tools), `measure.sh pattern`, `guard` on `PATTERN`/`RULE_FILE`; no eval run | F3d-2 |
| F4 Codex | backlog (D5) | — | — | — |
| F5 Profile L | ☐ wave G | `2026-10-29-…-f5-plan.md` | — | after F3 and F6; ships only with Δ > 0 per component, else v0.4 (D52) |
| F6 Feedback → infrastructure | ☐ wave E | `2026-10-29-…-f6-plan.md` | — | after F2d, F3b, F3c-1 |
| R Release v0.3.0 | ☐ wave H | `2026-10-29-…-r-plan.md` | — | last |
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

**Order from here (2026-10-29, owner: write every plan and delegate each to a subagent; the owner's session validates and merges each one):**
A: H1 ∥ F2c-1 → B: F2c-2 → C: F2c-3 → D: F2d ∥ F3b ∥ F3c-1 → E: F3c-2 ∥ F3d-1 ∥ F6 → F: F3d-2 → G: F5 → H: R.
Every agent follows `docs/plans/2026-10-29-keel-harness-v0.3-agent-rules.md` and runs no paid command.
The owner's paid steps (E3, then re-running the eval groups after F2c, F3d and F5) can run at any
time after the phase they measure.

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
- [x] `scripts/keel` with `plan | approve | apply | verify | measure | check`; approvals in
  `.agents/run/flow/`; `apply` refuses without an approval matching the proposal hash. Done in F2c-2;
  `build`, `rules` and `assess` call it, `contracts/flow.md` has the Phases.
- [x] `contracts/` (`sensor.md`, `rule-env.md`, `state.md`, `flow.md`, `plan.md`), moved from the skills'
  references. Done in F2c-1; `flow.md` is a stub until F2c-2 (Phases) and F2c-3 (Traceability).
- [ ] `contracts/rule-env.md` gains `ENFORCEMENT_LEVEL=mandatory|ratchet` (default `ratchet`).
  `harness-check` warns on a `mandatory` rule without a computational sensor. `AGENTS.md` lists the
  `mandatory` rules first. `rules` reads `.specify/memory/constitution.md` when it is present.
- [x] Rewrite each SKILL.md on the template in spec §5.5, one skill at a time: **assess (with
  doctor folded in), then build, then rules**. Each prose self-verify list moves into
  `keel verify <skill>`. Done in F2c-3; `tests/keel_template_test.sh` pins the five headings.
- [x] `disallowed-tools: Write Edit NotebookEdit` on `assess`.
- [x] `tests/keel_skill_size_test.sh`: every SKILL.md under 20,000 bytes.
- [x] Traceability matrix (`contracts/flow.md`): every `never`/`always` in a skill maps to a test, a
  `keel verify` item or an eval grader, classified by form (recipe / slot / discipline). Done in F2c-3;
  `tests/keel_traceability_test.sh` keeps it complete; the `none` rows are the open gaps.
- [x] Pressure tests for the discipline rules. Done in F2c-3 for `assess` (three `--tag pressure` cases, written, not run).
  - `assess` is read-only, so with/without evals in a cloud session can test it.
  - For `build` and `rules`, "write nothing before the user accepts" is enforced by `keel apply` and
    covered by its tests; the `tools` group (E3) measures the effect.
- [ ] Acceptance:
  - ported tests green;
  - merged `assess` not worse than E2 on `doctor-*` and F1 on `assess-*`;
  - `build-*` and `rules-*` not worse than E3 (re-run on the owner's machine);
  - `validate --strict` ok;
  - a v0.2 repository upgrades through `build` with a green gate.
  - Status 2026-10-29: the test suite is green (1755 `ok`) and `validate --strict` passes; the
    eval comparisons above are not re-run (owner, paid).

### F2d — assess and context

- [x] `assess` gains flakiness (run the suite N times), build reproducibility, headless setup and
  observability signals, each with evidence and cost, still with no aggregate score.
- [x] `build` proposes the stack's official LSP plugin. `rules` writes the codemap into
  `docs/architecture.md`, and `harness-check` warns `codemap-stale` on cited paths that no longer exist.
- [x] Triggering evals for each skill, should and should not trigger. They are read-only, so they run (written in F2d; not run, the owner runs them).

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

- [x] Plan template with a required **Acceptance** section in the sensors' numbers (spec-anchored,
  kept small). `.agents/plans/` stops being git-ignored.
- [x] Lifecycle `active | done | abandoned` in each plan's header. `keel` removes a `done` plan after
  its ADR or commit is referenced. `harness-check` warns `plan-stale` (active and untouched for 30
  days, adjustable) and `progress-size` (over 200 lines, adjustable).
- [x] `.agents/progress.md`, pointed at by `AGENTS.md`; `keel verify` rejects a plan without Acceptance.
- [x] Spec traceability (D46): specs are read from `docs/specs/` or an existing Spec Kit layout, and
  `harness-check` warns `acceptance-untested` when an acceptance criterion names no test.

## F3c — Authority (C7 + R)

- [x] `contracts/consequence.md` and a generated `.agents/consequence.yml` (paths × category: auth,
  data, infra, public contract, harness). (F3c-1)
- [x] From it: (F3c-1)
  - [x] deny rules merged into `.claude/settings.json`;
  - [x] `assets/adapters/claude/claude-protect.sh` (PreToolUse), which denies edits to `harness` paths
    and names the approved route in the reason;
  - [x] CODEOWNERS entries for consequential paths (proposed, owners only as the user gives them).
- [ ] `mandatory` rules (D43):
  - `guard` rejects loosening even when an added ADR names the file;
  - their env files and exception lists are protected paths;
  - their sensors are a required CI check;
  - an amendment is a superseding ADR approved through CODEOWNERS.
- [x] Sandbox / devcontainer as an option for profile L, with the trade-off stated. (F3c-1,
  `skills/build/references/authority.md`, documentation only)
- [ ] Hook and `guard` tests show that editing a baseline is denied (hook half done in F3c-1,
  `tests/keel_protect_test.sh`) and that a `mandatory` rule cannot be loosened (F3c-2).

## F3d — Exemplars and catalog

- [x] `EXEMPLAR=` in rule env files, a "follow X, not Y" line in nested `AGENTS.md`, legacy zones
  marked. (F3d-1)
- [ ] Catalog entries: function length, cyclomatic complexity, max parameters, optional dead code /
  duplication, and the ten D44 entries: `comments`, `spelling`, `code-style`, `naming`,
  `suppressions`, `dependencies`, `type-strictness`, `error-handling`, `logging`, `test-conventions`.
  Each comes with sensor tests.
- [x] A generic `pattern` sensor (ast-grep / semgrep / grep) for a team's own approved rules. (F3d-1)
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
