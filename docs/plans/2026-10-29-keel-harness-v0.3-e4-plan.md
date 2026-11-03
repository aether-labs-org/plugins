# keel-harness v0.3 — E4 Re-measure the read-only groups: Implementation Plan

> **For agentic workers:** this plan spends money. Run it in a Claude Code cloud session (where E1 and E2 worked) or any host where the nested Bash sandbox works. Read `docs/plans/2026-10-29-keel-harness-v0.3-agent-rules.md` first. That file's ban on paid commands is lifted here **only** for the `claude plugin eval` commands below, and **only** after the owner approves a ceiling in writing. Phase id: `e4`.

**Goal:** Measure the skills as they are after F2c–F6, so 0.3.0 ships with real numbers (owner's decision 2026-10-29: 0.3.0-rc.1 now, 0.3.0 after E3 and E4). F1 and E2 measured the skills before:
- F2c folded `doctor` into `assess` and rewrote all three skills on the template;
- F2d added four rubric axes;
- F3b, F3c and F6 added health checks.

This plan covers the groups a cloud session can run. E3 covers the tool cases on the owner's machine.

| Group | Cases | Grant | Compare with |
| --- | --- | --- | --- |
| `readonly` | `assess-mature-repo`, `assess-claude-md`, `should-not-trigger`, nine `trigger-*` | none | F1 / E2 for the first three; the trigger cases are new |
| `bash` | `assess-finds-drift`, `assess-validator-drift`, three `assess-pressure-*` | `--allow-tools Bash` | E2 (as `doctor-*`) for the first two; the pressure cases are new |

**Proposed ceiling: USD 10.** E2 spent USD 1.00 on three read-only cases and USD 1.17 on two Bash cases, both at 3 runs per arm. The nine trigger cases have `max_turns: 3`. This estimate is a hypothesis; the smoke run checks it.

## Tasks

- [ ] **Task 1 — host and branch** (free).
  1. Create `feat/keel-harness-v0.3-e4` from `origin/claude/harness-engineering-autonomous-agents-d8xhvx` and note the commit `<C>`.
  2. Check the host as in `docs/plans/2026-10-28-keel-harness-v0.3-f1b-plan.md` Task 1: nested `bwrap`, `gitleaks` ≥ 8.19, npm with network. In a cloud container, apply the npm `cafile` fix.
  3. Run `claude plugin validate ./plugins/keel-harness --strict`.
- [ ] **Task 2 — smoke** (paid, at most USD 1, the only run before approval). From `plugins/keel-harness/`:

```bash
claude plugin eval . --tag bash --runs 1 --scaffold --trust-plugin --allow-tools Bash \
  --no-publish --max-cost-usd 1 --json /tmp/e4-smoke.json
```

  **Qualification:**
  - every `assess-*` case reports its `skill-fired` indicator;
  - the four write graders are present;
  - no Bash call failed with `Read-only file system`.
- [ ] **Task 3 — HARD STOP.** Send the owner the smoke cost, the estimate for both groups at 3 runs per arm, and the proposed ceiling. Wait for written approval.
- [ ] **Task 4 — measured runs:**

```bash
claude plugin eval . --tag readonly --scaffold --trust-plugin --no-publish --max-cost-usd <A> --json /tmp/e4-readonly.json
claude plugin eval . --tag bash --scaffold --trust-plugin --allow-tools Bash --no-publish --max-cost-usd <B> --json /tmp/e4-bash.json
```

  - Exit 2 means the ceiling was hit: stop and report the partial results.
  - Exit 1 is data, not an error.
  - Do not re-run to chase a number.
- [ ] **Task 5 — record.**
  1. Copy the JSON files to `docs/evals/keel-v0.3-e4/`.
  2. In the README, under the E2 results, add **"E4 results"**: date, Claude Code version, `<C>`, host, total cost, and a `Case | WITH | W-OUT | Δ | Cost (USD)` table.
  3. Add one line per case that has an earlier row, saying what changed between the two measurements.
  4. For each new case with Δ ≤ 0, add a short finding.
  5. Tick E4 in the master plan.
  6. Commit `docs(keel-harness): E4 results` and push. No pull request.

## Acceptance

- Both groups were measured under an approved ceiling, and the raw results are committed.
- D51's bar is checked and stated in the README:
  - merged `assess` vs E2 on `assess-*-drift`;
  - merged `assess` vs F1 on `assess-*`.
- The R2 step (version `0.3.0`, the proven/unproven table) can then be written from E3 and E4.
