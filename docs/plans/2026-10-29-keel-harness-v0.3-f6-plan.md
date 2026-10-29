# keel-harness v0.3 — F6 Feedback into infrastructure: Implementation Plan

> **For agentic workers:** read `docs/plans/2026-10-29-keel-harness-v0.3-agent-rules.md` first. Phase id: `f6`. Free; no eval. Starts after F2d, F3b and F3c-1 are merged. F3c-2 and F3d-1 run in parallel with you. Add `harness-check` checks as new functions placed just before `# --- review-due`.

**Goal:** spec C9 and D41; evidence §9 items 1, 2, 3 and 9. Recurring problems should improve the controls. Read D41's `doctor` as `assess` (D51). keel records what happens, `assess` reports what it means, and nothing is promoted without approval.

## Tasks

- [ ] **Task 1 — gate history** (tests first, `tests/keel_gate_test.sh`).
  - Each `gate.sh` run appends one TSV line per sensor to `.agents/run/history/<fast|slow>.tsv`: `<UTC ISO time><TAB><sensor id><TAB><status><TAB><ms>`.
  - It keeps only the last `HISTORY_RUNS` runs, default 50, read from `.agents/gate.env` with the existing parser. A run is all lines sharing a timestamp. Trim with `awk` into a temp file per H1's rule, then `mv`.
  - A failure to write history never changes the gate's verdict or exit code.
  - Add `HISTORY_RUNS=50` to `assets/core/gate.env` with a comment.
  - Commit `feat(keel-harness): gate keeps the last N runs per sensor in .agents/run/history/`.
- [ ] **Task 2 — `harness-check` reads the history:**
  - **`sensor-always-green`:** a sensor that passed in every one of at least 30 recorded runs and never failed. The message asks whether it still carries load (Rajasekaran: remove components that stopped being load-bearing). Fix: `review it; remove it or move it to the slow gate`.
  - **`sensor-always-red`:** failed in every one of the last 10 runs. Fix: `fix the cause or re-baseline with an ADR`.
  - **`sensor-flaky`:** alternated pass/fail on runs without changes, at least 3 flips in the last 10. Fix: `make it deterministic`. Changes are not recorded, so this is a heuristic; say so in the message.
  - Silent with fewer runs than each threshold.
  - Add them to the checks table and update the count. Test with fixture history files.
  - Commit `feat(keel-harness): harness-check reports always-green, always-red and flaky sensors`.
- [ ] **Task 3 — lessons inbox.**
  - `contracts/learnings.md`: `.agents/run/learnings/YYYY-MM-DD-<slug>.md`, git-ignored, with headers `Source:` (session, review comment or gate failure), `Seen:` (count), `Proposed:` (`rule | sensor | adr | discard`).
  - **Who writes:**
    - `assets/core/README.agents.md` tells any agent to write a lesson there when a review comment or repeated failure teaches something;
    - the Stop hook writes one automatically when the same sensor fails 3 sessions in a row. Implement it in `claude-stop.sh` with a test in `tests/keel_stop_hook_test.sh`, and keep it under the hook's timeout.
  - **`assess`** (health-check phase) lists inbox items and proposes, per item, the promotion route: `/keel-harness:rules` for a rule or sensor, an ADR, or discard. It never promotes by itself.
  - Commit `feat(keel-harness): lessons inbox and assess promotion proposals (D41)`.
- [ ] **Task 4 — auto-memory coherence.**
  - Find Claude Code's auto-memory location and format in `https://code.claude.com/docs/en/memory`; cite it with the date.
  - `assess` reads the project's auto-memory file when it exists and reports each entry that contradicts a rule. A contradiction is a statement about a rule's subject that differs from its env-file numbers or `AGENTS.md` line; this is inferential, so say so in the report.
  - It **never edits memory**. It proposes the user edit or delete the entry.
  - Document the step in `skills/assess/references/`. Commit `feat(keel-harness): assess reports auto-memory entries that contradict a rule (D41)`.
- [ ] **Task 5 — adherence diagnosis** (spec §5.4).
  - `skills/assess/references/adherence.md`: a prompt-style procedure, in the spirit of superpowers' `plan-adherence` (cited in spec §9 item 5), for reading a session transcript the user points at. Did the flow's phases happen, in order? Was `keel apply` before the first write? Did `keel verify` run at the end?
  - Report a per-phase yes/no with the transcript line. Opt-in only: `assess` offers it when the user asks how well agents follow the harness.
  - Commit `docs(keel-harness): adherence diagnosis procedure`.
- [ ] **Task 6 — recurring failures and model changes.**
  - `harness-check` check **`failure-recurring`**: the same sensor failing in at least 5 of the last 20 runs. Each warning names the sensor's guidance and suggests the guide (`AGENTS.md` line, `docs/` section, exemplar) that would have prevented it.
  - `assets/core/README.agents.md` and the README get "On a model change: re-run the read-only eval groups and move `harness_review_by`".
  - Tests. Commit `feat(keel-harness): recurring failures point at the guide that would prevent them`.
- [ ] **Task 7 — master plan:** tick F6, mark it ✅. Commit `docs(keel-harness): F6 done`.

## Acceptance

- The gate verdict and exit code are byte-identical with and without a writable history directory; a test proves it.
- Each new `harness-check` check has warn, clean and below-threshold tests.
- `assess` never writes memory or learnings, and proposes only. `tests/assess_test.sh` asserts the prohibition, and the traceability matrix gains the rows.
- `./tests/run.sh` exits 0; `validate --strict` passes; `shellcheck` is clean; the size limits hold.
