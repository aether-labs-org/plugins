# keel-harness v0.3 — F5 Profile L components: Implementation Plan

> **For agentic workers:** read `docs/plans/2026-10-29-keel-harness-v0.3-agent-rules.md` first. Phase id: `f5`. Free; no eval run (cases may be written). Starts after F3 and F6 are merged.

**Goal:** spec profile L and components C3, C8, C10; D47, D52. Build the three profile-L components so they can be measured. **D52:** each ships in v0.3 only if a with/without measurement shows Δ > 0. That measurement is the owner's paid step, so everything here is marked `experimental — unproven (D52)` until then, and phase R decides what ships.

## Tasks

- [ ] **Task 1 — C3: an inferential reviewer sensor** (slow gate only, opt-in).
  - **The asset:** `assets/core/sensors/slow/reviewer.sh`, class `heuristic`.
  - **What it reviews:** the diff since the base (`KEEL_GUARD_BASE` logic, as `guard`) against the repository's rules (`AGENTS.md` and the cited `docs/` sections).
  - **How it calls the model:** through a command the user configures, `REVIEWER_CMD` in `.agents/rules/reviewer.env`, e.g. `claude -p --model <a different model than the one coding>`, or any CLI that reads a prompt on stdin and prints a verdict.
    - This is the **one allowed exception** to "no model call in installed scripts". It lives only in `slow/` and is never in the fast gate. With no `REVIEWER_CMD`, or the command not on `PATH`, it skips (exit 2).
  - **Budget:** `MAX_DIFF_LINES` (default 800; skip above it) and `TIMEOUT_SECONDS` (default 120).
  - **Output contract:** the model must answer with `PASS` or `FAIL: <reason>` lines. Anything else is a skip ("unparseable verdict"), never a pass.
  - **Calibration fixture:** `tests/fixtures/keel/reviewer/` holds one diff that violates a rule and one that does not, plus a stub `REVIEWER_CMD` for the tests. Tests use only the stub; no network.
  - `build` and `rules` mention it as an optional slow sensor for profile L, with the cost stated.
  - Commit `feat(keel-harness): optional reviewer sensor in the slow gate (C3, experimental)`.
- [ ] **Task 2 — C8: a journey sensor for web stacks** (slow, opt-in).
  - **The asset:** `assets/core/sensors/slow/journey.sh` runs the project's Playwright journeys: `npx playwright test <JOURNEY_DIR>` from `.agents/rules/journey.env`, with JSON or line reporter output reduced to the sensor contract. It skips when Playwright is not installed.
  - **Guidance on fail:** the failing journey and its trace path.
  - **Logs:** structured-log guidance in `skills/build/references/context-engineering.md`: a JSON log line shape agents can grep, and why.
  - **Tests:** stub `npx`, in the style of `tests/fixtures/keel/stubs/`.
  - Commit `feat(keel-harness): journey sensor and structured-log guidance (C8, experimental)`.
- [ ] **Task 3 — C10: orchestration recipe (documentation only, D47).**
  - Write it in `assets/core/README.agents.md` (short) and the plugin README (full):
    - one planner pass writes `.agents/plans/<plan>.md` with Acceptance (F3b);
    - one main loop owns state and uses stateless subagents for read-heavy work;
    - the gate after each step;
    - the reviewer sensor or an evaluator subagent at the end;
    - `.agents/progress.md` across sessions.
  - Name the runners: superpowers' `executing-plans` / `subagent-driven-development`, the Agent SDK, or a `claude -p` loop.
  - keel orchestrates nothing.
  - Commit `docs(keel-harness): autonomous-run recipe (C10, D47)`.
- [ ] **Task 4 — eval cases for D52** (files only, tag `[profile-l, tools]`):
  - **`reviewer-catches-violation`:** a repository with a rule and a planted violating diff; `make gate-slow` with the real reviewer.
    - With/without here means **with the reviewer sensor installed vs not**. Use two case directories, as `rules-effect-with/-without` do; tag them `effect` as well.
  - **`journey-catches-regression`:** a minimal web fixture with one journey and a planted regression.
  - Make `tests/keel_evals_test.sh` pass, extending its group logic minimally if needed.
  - Commit `test(keel-harness): profile-L eval cases (D52)`.
- [ ] **Task 5 — master plan:** tick F5 items, and mark the status row "◐ built; ships per D52 after the owner's measurement". Commit `docs(keel-harness): F5 built, pending D52 evidence`.

## Acceptance

- `reviewer.sh` and `journey.sh` follow the sensor contract. They skip without configuration, never pass on an unparseable verdict, and are tested with stubs only.
- No installed script outside `slow/reviewer.sh` calls a model; a test greps it.
- The recipe names concrete runners and keeps keel out of orchestration.
- The eval cases exist and pass `tests/keel_evals_test.sh`.
- `./tests/run.sh` exits 0; `validate --strict` passes; `shellcheck` is clean.
