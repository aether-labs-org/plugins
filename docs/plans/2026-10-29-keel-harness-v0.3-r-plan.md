# keel-harness v0.3 — R Release 0.3.0: Implementation Plan

> **For agentic workers:** read `docs/plans/2026-10-29-keel-harness-v0.3-agent-rules.md` first. Phase id: `r`. Free; no eval. Starts after every other v0.3 phase is merged. Mechanical work: change only what is listed.

**Goal:** publish v0.3.0 with an honest record of what is proven and what is not.

## Tasks

- [ ] **Task 1 — version.**
  - `plugins/keel-harness/.claude-plugin/plugin.json` → `"version": "0.3.0"`.
  - `tests/structure_test.sh`: the expected version → `0.3.0`, and an assertion that the v0.3 spec's status line reads `implemented in v0.3.0`.
  - Spec `docs/specs/2026-10-23-keel-harness-v0.3-design.md` `**Status:**` → `implemented in v0.3.0 (YYYY-MM-DD); see the master plan's status table for what is unproven`. The v0.2 spec keeps its own status.
  - Commit `chore(keel-harness): 0.3.0`.
- [ ] **Task 2 — README** (`plugins/keel-harness/README.md`):
  1. **Skills section:** `assess` (readiness and health check), `build`, `rules`. No `doctor` anywhere except the breaking-change note.
  2. **"What's new in 0.3"**, one line per item:
     - CI and pre-commit layers;
     - `guard`;
     - `scripts/keel` flow;
     - consequence map and protect hook;
     - mandatory rules;
     - versioned plans and progress;
     - exemplars and catalog entries;
     - feedback (history, lessons);
     - temp-dir hardening.
  3. **"Breaking changes":** `/keel-harness:doctor` → `/keel-harness:assess` (D51); `.agents/` run state moved to `.agents/run/` (F2b, upgraded by `build`); `.agents/plans/` is now committed (F3b).
  4. **"Proven and unproven":** a table built from the master plan's status table and the eval sections:
     - each skill and component;
     - its latest with/without Δ, with its date and phase;
     - or `unproven`.

     Profile L is `partial` unless every F5 component has Δ > 0 (D52). Do not invent numbers; copy them from the README's eval sections.
- [ ] **Task 3 — marketplace.** If the plugin's description changed, update `.claude-plugin/marketplace.json` and `plugin.json` to the same text. Commit tasks 2–3: `docs(keel-harness): 0.3.0 README and marketplace`.
- [ ] **Task 4 — checks.**
  - `make check` and `make validate` are green.
  - `grep -rn "0.2.0" plugins/keel-harness` matches only historical text.
- [ ] **Task 5 — master plan:** mark R ✅. Commit `docs(keel-harness): R done`.
  - **Do not open a pull request.** The owner decides on a PR to `main`.

## Acceptance

- Version 0.3.0 is everywhere it is tested.
- The README's proven/unproven table matches the master plan, with no invented numbers.
- `make check` and `make validate` are green.
