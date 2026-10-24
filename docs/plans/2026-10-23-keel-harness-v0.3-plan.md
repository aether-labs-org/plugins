# keel-harness v0.3 Implementation Plan

**Goal:** Take keel-harness from v0.2.0 to v0.3 as specified in
`docs/specs/2026-10-23-keel-harness-v0.3-design.md` — fix the v0.2 defects, measure the current
plugin, refactor it into the v0.3 layout with flows enforced in code, and then close the criterion's
gaps profile by profile.

**Spec:** read `docs/specs/2026-10-23-keel-harness-v0.3-design.md` before F0. Each phase cites the
spec section it implements.

**Order:** F0 → F1 → F2 → (F3a ∥ F3b ∥ F3d) → F3c → F5. F6 may start once F2 is done. F4 is backlog.

**Effort** is relative (S / M / L), not days: nothing here has been measured yet.

## Global constraints

- Everything installed in a target repository stays plain bash 3.2, no `jq`, no network, no model
  call, and runs with the plugin absent (v0.2 D26 and sensor contract §6).
- Installed paths (`scripts/gate.sh`, `scripts/sensors/`, `.agents/`) do not move; v0.3 only adds
  files. A v0.2 install upgrades in place under confirmation.
- `make check` and `make validate` stay green after every task; each phase ends with its acceptance
  criteria checked and the README eval table updated where evals ran.

## Summary

| Phase | Deliverables | Impact | Effort | Depends on | Risk | Acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| **F0 Fixes** | D-1 `guard` sensor; D-2 parser; D-3; D-4; D-5 | High | S | — | Low | D-1 reproduction is a test: fails without a record, passes with one; no `eval` of config; suite green |
| **F1 Measure** | Run the 15 v0.2 evals with/without, with token cost per case | High (the ruler for F2+) | M ($) | F0 | Medium (host) | README table filled; Δ and cost recorded; any Δ ≤ 0 written up |
| **F2 Refactor** | v0.3 layout; `scripts/keel` phases; `contracts/`; skill template; `disallowed-tools`; skill-size test; form × failure pass; pressure tests; `assess` dimensions; `schema_version: 3` upgrade | High | L | F1 | Medium | Ported tests green; evals not worse than F1; traceability 100 %; `validate --strict` ok; a v0.2 repo upgrades with a green gate |
| **F3a CI + pre-commit** | `assets/core/ci`, `assets/core/precommit` | High | S | F2 | Low | A planted defect is red in pre-commit and in CI |
| **F3b Versioned plans** | Plan template with Acceptance; progress file | Medium | S | F2 | Low | `keel verify` rejects a plan without Acceptance; a new session resumes from the progress file |
| **F3c Authority (C7 + R)** | Consequence map; settings deny; `claude-protect.sh`; CODEOWNERS; sandbox option | High | M | F3a | Medium | Eval: editing a baseline is blocked; a consequential path requires a reviewer |
| **F3d Exemplars + catalog** | `EXEMPLAR=`, legacy zones; function length, complexity, max params, dead code | Medium | M | F2 | Low | Each entry passes a with/without ablation or is removed |
| **F4 Codex** *(backlog)* | `.codex-plugin/`, `assets/adapters/codex/` | Medium | M | F2 | Medium | Same cases with Δ > 0 under Codex |
| **F5 Profile L** | C3 reviewer (different model, budgeted); C8 journey sensor; C10 documented only | Medium | L | F3 | High | Each component passes its ablation; Δ ≤ 0 means it is removed |
| **F6 Feedback → infrastructure** | Sensor state history; transcript adherence diagnosis; `doctor` proposes controls for recurring failures; review on model change | Medium | M | F2 | Low | On a fixture with history, `doctor` names the inert sensor and the recurring failure class |

---

## F0 — Fixes (spec §6, D32, D33)

- [ ] **D-1 `guard` sensor.** Add `rules/assets/sensors/guard.sh` (class `security`: no baseline of
  its own). Compare, against `HEAD`: every `.agents/baselines/*.tsv` row count (a row that rises or
  a new row fails); every numeric `LIMIT|MIN|MAX|THRESHOLD` key in `.agents/rules/*.env` that
  loosens; `CEILING_SECONDS` / `SLOW_CEILING_SECONDS` in `.agents/gate.env` that grow. A loosening
  passes only when the same diff adds the file named by `LOOSENED_BY=` in the rule's env file (or a
  `# loosened_by: docs/decisions/NNNN-*.md` line in the baseline header), and that file exists.
  Guidance names the record route and says that editing the sensor is the wrong fix.
- [ ] Turn the reproduction from the review into `tests/keel_guard_test.sh`: 20-line file with
  `LIMIT=10` → `file-size` fails; baseline row added without a record → `guard` fails; with a
  record → passes; baseline row removed → passes.
- [ ] `build` installs `guard` with every harness; `harness-check.sh` warns when it is missing.
- [ ] **D-2.** Add `lib/envparse.sh` (`KEY=value`, quotes, comments, CRLF, multi-line values the
  rule files already use) and replace the nine `eval "$(tr -d '\r' < "$RULE_ENV")"` calls. Reject
  a value containing `$(` or a backtick with a `fail` that names the file.
- [ ] **D-3.** Replace the two `reasoning-framework.md` references in
  `assess/references/harness-model.md` with the sections that exist, or drop them.
- [ ] **D-4.** Reword `build/SKILL.md` §7: `PostToolUse` exit-0 stdout goes to the debug log and exit 2
  shows only stderr, so the report never reaches Claude intact (as v0.2 spec §14.1 says).
- [ ] **D-5.** In `tests/keel_assets_test.sh`, report `skip` when `shellcheck` is not installed
  locally; CI keeps it required.

**Done when:** the acceptance in the summary holds and `make check` is green.

## F1 — Measure the current plugin (spec §2.2 C9, D31)

- [ ] Pick a host without the nested user-namespace restriction documented in the README.
- [ ] Run every case in `evals/` with and without the plugin, three runs per arm; record WITH,
  W-OUT, Δ and **token cost per case**.
- [ ] Run `rules-effect-with` / `-without` with `--ablation none` and compare by hand.
- [ ] Fill the README table. Write up every case with Δ ≤ 0 as a finding; v0.2's existence floor
  (rewrite or delete after three runs with Δ ≤ 0) still applies.

## F2 — Refactor (spec §4, §5, D29, D34–D38)

Migrate one skill at a time — **doctor, then assess, then build, then rules** — and run that
skill's evals after each step against the F1 numbers.

- [ ] Create `assets/core/`, `assets/adapters/claude/`, `scripts/`, `contracts/`; move assets with
  `git mv` so history follows; update every `${CLAUDE_SKILL_DIR}` path that crosses skills to
  `${CLAUDE_PLUGIN_ROOT}`.
- [ ] `scripts/keel` with `plan | approve | apply | verify | measure | check`; `.agents/flow/`
  git-ignored; `apply` refuses without an approval matching the proposal hash.
- [ ] Rewrite each SKILL.md on the template in spec §5.5; move each prose self-verify list into
  `keel verify <skill>`.
- [ ] `disallowed-tools: Write Edit NotebookEdit` on `assess` and `doctor`.
- [ ] `tests/keel_skill_size_test.sh`: every SKILL.md under 20,000 bytes.
- [ ] Traceability matrix (`contracts/flow.md`): every `never`/`always` in a skill → a test, a
  `keel verify` item or an eval grader. Classify each by form (recipe / slot / discipline).
- [ ] A pressure test (with/without eval) for each discipline rule, starting with "write nothing
  before the user accepts".
- [ ] `assess` gains flakiness (run the suite N times), build reproducibility, headless setup and
  observability signals, each with evidence and cost, still with no aggregate score.
- [ ] `state.yml` `schema_version: 3`; `build` upgrades v0.2 installs in one round, item by item.
- [ ] Triggering evals for each skill (should and should not trigger).

## F3a — CI and pre-commit (D7 revised)

- [ ] `assets/core/ci/keel.yml`: on pull request, `make gate-fast`, `make harness-check`, and `guard`
  over the PR diff; `gate-slow` behind an opt-in input.
- [ ] `assets/core/precommit/`: lefthook, pre-commit and husky variants; `build` proposes the one the
  repository already uses, or none.
- [ ] `harness-check.sh` warns when local and CI commands diverge.

## F3b — Versioned plans and progress (D6 revised)

- [ ] Plan template with a required **Acceptance** section in the sensors' numbers (spec-anchored,
  kept small); plans move from `.agents/plans/` (ignored) to a versioned path the user approves.
- [ ] A progress file the Stop-hook report and `AGENTS.md` point at; `keel verify` rejects a plan
  without Acceptance.

## F3c — Authority (C7 + R)

- [ ] `contracts/consequence.md` and a generated `.agents/consequence.yml` (paths × category:
  auth, data, infra, public contract, harness).
- [ ] From it: deny rules merged into `.claude/settings.json`; `assets/adapters/claude/claude-protect.sh`
  (PreToolUse) denying edits to `harness` paths with the approved route in the reason; CODEOWNERS
  entries for consequential paths.
- [ ] Sandbox / devcontainer as an option for profile L, with the trade-off stated.
- [ ] Evals: an attempt to edit a baseline is blocked; a consequential change requests a reviewer.

## F3d — Exemplars and catalog

- [ ] `EXEMPLAR=` in rule env files and a "follow X, not Y" line in nested `AGENTS.md`; legacy zones
  marked.
- [ ] Catalog entries: function length, cyclomatic complexity, max parameters (the thresholds
  presets omit), and optional dead code / duplication (knip, deadcode).
- [ ] One with/without ablation per entry; remove what shows Δ ≤ 0.

## F4 — Codex adapter (backlog, D5)

- [ ] `.codex-plugin/plugin.json` beside the existing manifest, one shared `skills/`.
- [ ] `assets/adapters/codex/` running the fast gate from a Codex Stop hook (`hooks.json`).
- [ ] The same cases under Codex.

## F5 — Profile L

- [ ] C3: an optional reviewer sensor that calls a different model, with a token budget and a
  calibration fixture; never in the fast gate.
- [ ] C8: a journey sensor (Playwright) for web stacks, plus structured-log guidance.
- [ ] C10: documentation only.
- [ ] Ablation per component; remove what is not load-bearing.

## F6 — Feedback into infrastructure

- [ ] Append each gate run's per-sensor status to a git-ignored history; `doctor` reports sensors
  that are always green or always red.
- [ ] Transcript adherence diagnosis (did the flow's phases happen, in order) as a `doctor` mode.
- [ ] `doctor` groups recurring failures by class and proposes the guide or sensor that would have
  prevented them.
- [ ] On a model change, re-run the F1 ablations and move `harness_review_by`.
