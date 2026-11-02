# keel-harness v0.3 — F2c-1 Contracts and assess ⊃ doctor: Implementation Plan

> **For agentic workers:** read `docs/plans/2026-10-29-keel-harness-v0.3-agent-rules.md` first. Phase id: `f2c1`. Free; no eval run (evals are edited, not run).

**Goal:** First third of F2c (master plan §F2c; spec §4, §5.2, §5.5, D36, D38, D51):
1. **`contracts/`** at the plugin root, the single source every skill points at, replacing cross-skill reference paths.
2. **`doctor` folded into `assess` (D51).** One read-only skill: the rubric when no harness is installed, the validator plus explanations when one is.
3. **`disallowed-tools: Write Edit NotebookEdit`** on `assess` (D36).
4. **A size test:** every SKILL.md under 20,000 bytes (D38).

F2c-2 (`scripts/keel` flow) and F2c-3 (build and rules on the skill template, traceability) follow. Do not start them here.

## Task 1 — `contracts/`

- [ ] Create `plugins/keel-harness/contracts/` with `git mv` (keep history):

| New file | From |
| --- | --- |
| `contracts/sensor.md` | `skills/build/references/sensor-contract.md` |
| `contracts/rule-env.md` | `skills/rules/references/rule-env.md` |
| `contracts/plan.md` | `skills/rules/references/plan-template.md` |
| `contracts/state.md` | **new**: the `.agents/state.yml` schema |
| `contracts/flow.md` | **new**: a stub with a `## Phases` and a `## Traceability` heading, each saying "filled in F2c-2 / F2c-3" |

- [ ] **`contracts/state.md`**, the schema as it is today:
  - `schema_version: 3`, `installed_at`, `harness_review_by`, `mode`, `adr_dir`;
  - `layers` with the keys `bootstrap guides fast_gate slow_gate hook ci precommit rules`, each `installed | not_installed`. `ci` and `precommit` are optional (F3a);
  - `not_installed` (layer or sensor → reason).

  For each key: type, who writes it (build or rules), and who reads it (`harness-check`, `guard`). Take the facts from `skills/build/SKILL.md` §9, `skills/rules/SKILL.md` and `assets/core/harness-check.sh`. `build/SKILL.md` §9 keeps its YAML example but points at `contracts/state.md` for the meaning of each key.
- [ ] Update every reference to the moved files. Find them with `grep -rn "sensor-contract.md\|rule-env.md\|plan-template.md" plugins tests` and fix:
  - skills;
  - `assess/references/harness-model.md`;
  - `assets/core/harness-check.sh`: only if it names the file in a message; installed scripts must not point into the plugin, so name it as "keel's sensor contract";
  - the README and tests.

  Skills reach contracts as `${CLAUDE_PLUGIN_ROOT}/contracts/<file>`. A skill's own `references/` stays relative.
- [ ] `tests/keel_layout_test.sh`: assert the five contract files exist and that no SKILL.md or reference contains `../build/` or `../rules/` (cross-skill paths).
- [ ] Commit `refactor(keel-harness): contracts/ as the single source for sensor, rule-env, plan, state and flow`.

## Task 2 — fold `doctor` into `assess`

- [ ] **New `skills/assess/SKILL.md`** (stay well under 20,000 bytes):
  - **Frontmatter.** `name: assess`. A merged `description` of at most 1,024 characters that keeps both trigger families, for example: "…ready for AI coding agents…", "…whether their harness is out of date, stale or still valid, or wants a harness health check…". Then `disallowed-tools: Write Edit NotebookEdit`.
  - **`## 0. Which question`.**
    - No `.agents/state.yml` → the readiness rubric: today's sections 1–5, unchanged in substance.
    - `.agents/state.yml` present → the health check: today's `doctor` sections 1–3.
    - When the user asks both, do both, health check first.
  - **The single rule** (writes nothing) stays first. Running `harness-check.sh` is allowed: it is read-only, and after H1 its only possible write is git-ignored temp state under `.agents/run/tmp/`.
  - **The fifteen-check table** moves to `skills/assess/references/checks.md`, with the "one condition, exactly one warning" rule. The skill links it.
  - **Validator drift** (the `cmp` against `${CLAUDE_PLUGIN_ROOT}/assets/core/harness-check.sh`) and the `/doctor prompt-audit` pointer move over unchanged.
  - **Fix the stale sentence** in today's §4: "Enforcement (pre-commit, CI) is not installed by keel". Since F3a, `build` proposes both layers (`skills/build/references/enforcement.md`). Report the gap and quote setup minutes like any other axis.
- [ ] `git rm -r plugins/keel-harness/skills/doctor`.
- [ ] **Evals.** Rename the cases with `git mv` and update everything that names them:
  - `evals/doctor-finds-drift` → `evals/assess-finds-drift`;
  - `evals/doctor-validator-drift` → `evals/assess-validator-drift`;
  - `case.yaml`: `name:` and `description:`; tag `doctor` → `assess` (keep `bash`);
  - the `assess-validator-drift` scaffold calls `../doctor-finds-drift/scaffold.sh`: fix the path;
  - add `graders/skill-fired.md` to both (`type: tool_used`, `tool: Skill`, `input_match: '"skill"\s*:\s*"(?:[\w-]+:)?assess"'`), as `assess-mature-repo` has;
  - `should-not-trigger/graders/skill-silent.md`: `(assess|build|doctor|rules)` → `(assess|build|rules)`.
- [ ] **Tests.**
  - Merge `tests/doctor_test.sh` into `tests/assess_test.sh`; every assertion keeps its meaning, pointed at the new paths. Delete `doctor_test.sh`.
  - Add assertions that `skills/doctor` does not exist and that `assess` declares `disallowed-tools: Write Edit NotebookEdit`.
  - `tests/keel_evals_test.sh` must stay green with the renamed cases (its `should-not-trigger` check looks for `rules)`).
- [ ] **README** (`plugins/keel-harness/README.md`):
  - the skills section: `assess` covers both questions;
  - remove `/keel-harness:doctor`;
  - a short **"Breaking change in v0.3"** note under the skills section;
  - in the eval tables, the case names, with a note that `assess-*-drift` were `doctor-*-drift` before F2c (E1, E2 rows).
- [ ] Commit `feat(keel-harness)!: fold doctor into assess (D51); assess drops Write and Edit (D36)`.

## Task 3 — size test

- [ ] `tests/keel_skill_size_test.sh`: every `plugins/keel-harness/skills/*/SKILL.md` is under 20,000 bytes (`wc -c`). Also keep the existing 250-line check on `build`. Commit `test(keel-harness): SKILL.md under 20,000 bytes (D38)`.

## Task 4 — master plan

- [ ] In `docs/plans/2026-10-23-keel-harness-v0.3-plan.md`, tick the F2c items done here (contracts/, the doctor fold, disallowed-tools, the size test) and update the F2c status row ("◐ F2c-1 done"). Commit `docs(keel-harness): F2c-1 done`.

## Acceptance

- `ls plugins/keel-harness/skills` → `assess build rules`.
- `grep -rn "keel-harness:doctor\|skills/doctor" plugins tests` matches nothing, except the README's breaking-change note.
- Every SKILL.md is under 20,000 bytes; `assess` has `disallowed-tools`.
- `./tests/run.sh` exits 0; `validate --strict` passes.
- `assess/SKILL.md` no longer says that keel does not install enforcement.
- **Not covered here (owner, paid):** the merged `assess` scores no worse than E2 on `assess-*-drift` and no worse than F1 on `assess-*` (D51). List this as open in the report.
