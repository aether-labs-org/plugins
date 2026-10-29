# keel-harness v0.3 — R Release candidate 0.3.0-rc.1: Implementation Plan

> **For agentic workers:** read `docs/plans/2026-10-29-keel-harness-v0.3-agent-rules.md` first. Phase id: `r`. Free; no eval. Starts after every other v0.3 phase is merged. Mechanical work: change only what is listed.

**Goal:** publish **0.3.0-rc.1**, with an honest record of what is proven and what is not. Owner's decision (2026-10-29): the code is complete, but no paid eval has measured it. The final 0.3.0 waits for E3 (the 10 tool cases, owner's machine) and E4 (the read-only groups re-measured). Then a short R2 step only changes the version and the proven/unproven table.

## Tasks

- [ ] **Task 1 — version.**
  - `plugins/keel-harness/.claude-plugin/plugin.json` → `"version": "0.3.0-rc.1"` (checked: `claude plugin validate --strict` accepts it).
  - `tests/structure_test.sh`: the expected version → `0.3.0-rc.1`, and an assertion that the v0.3 spec's status line contains `release candidate 0.3.0-rc.1`.
  - Spec `docs/specs/2026-10-23-keel-harness-v0.3-design.md` `**Status:**` → `release candidate 0.3.0-rc.1 (YYYY-MM-DD): implemented, not yet measured; 0.3.0 after E3 and E4 (see the master plan)`. The v0.2 spec keeps its own status.
  - Commit `chore(keel-harness): 0.3.0-rc.1`.
- [ ] **Task 2 — README** (`plugins/keel-harness/README.md`):
  1. **Skills section:** `assess` (readiness and health check), `build`, `rules`. No `doctor` anywhere except the breaking-change note.
  2. **"What's new in 0.3 (release candidate)"**, one line per item, preceded by one sentence: this is a release candidate, built and tested but not yet measured with evals; 0.3.0 follows E3 and E4.
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

     Profile L components (reviewer, journey) are `experimental — unproven (D52)`: opt-in, off by default. Do not invent numbers; copy them from the README's eval sections, and mark every case measured before F2c with the commit it was measured at (the skills changed after it).
- [ ] **Task 3 — marketplace.** If the plugin's description changed, update `.claude-plugin/marketplace.json` and `plugin.json` to the same text. Commit tasks 2–3: `docs(keel-harness): 0.3.0 README and marketplace`.
- [ ] **Task 4 — checks.**
  - `make check` and `make validate` are green.
  - `grep -rn "0.2.0" plugins/keel-harness` matches only historical text.
- [ ] **Task 5 — master plan:** mark R "◐ 0.3.0-rc.1; 0.3.0 after E3 and E4". Commit `docs(keel-harness): 0.3.0-rc.1`.
  - **Do not open a pull request.** The owner decides on a PR to `main`.

## Acceptance

- Version 0.3.0-rc.1 is everywhere it is tested; no file claims a final 0.3.0.
- The README's proven/unproven table matches the master plan, with no invented numbers.
- `make check` and `make validate` are green.
