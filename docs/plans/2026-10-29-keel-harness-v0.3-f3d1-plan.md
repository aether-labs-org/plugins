# keel-harness v0.3 — F3d-1 Exemplars and the pattern sensor: Implementation Plan

> **For agentic workers:** read `docs/plans/2026-10-29-keel-harness-v0.3-agent-rules.md` first. Phase id: `f3d1`. Free; no eval. Starts after F2d, F3b and F3c-1 are merged. F3c-2 and F6 run in parallel with you. Add `harness-check` checks as new functions placed just before `# --- review-due`.

**Goal:** component C1b (exemplary code) and the generic sensor that F3d-2's catalog entries build on.
- An agent copies the pattern it sees nearest. keel lets the team point at the canonical example, mark legacy zones, and turn a syntactic pattern into a sensor.

## Tasks

- [ ] **Task 1 — exemplars.**
  - `contracts/rule-env.md`: optional `EXEMPLAR=<path>` and `LEGACY=` (multi-line quoted pathspecs) in any rule env file.
  - `skills/rules/references/nested-agents-md-template.md`: a `Follow <EXEMPLAR>, not <legacy path>` line, and a `Legacy zone:` line listing the `LEGACY` pathspecs with a pointer to the rule's plan.
  - `rules` proposes an exemplar per rule when the measurement shows a clear best file; the user confirms. It never invents one.
  - `harness-check` check **`exemplar-missing`**: an `EXEMPLAR` path that does not exist. Add it to the checks table and update the count.
  - Tests in `tests/keel_harness_check_test.sh` and `tests/rules_test.sh`.
  - Commit `feat(keel-harness): rule exemplars and legacy zones (C1b)`.
- [ ] **Task 2 — `assets/core/sensors/rules/pattern.sh`**, a generic, baselined sensor (tests first, `tests/keel_rule_sensors_test.sh`):
  - **Env** (`.agents/rules/<rule-id>.env`, the sensor copied as `scripts/sensors/<rule-id>.sh`, with `id` read from `RULE_ID`):
    - `PATTERN` (an ERE for `grep -E`);
    - `ENGINE=grep|ast-grep|semgrep` (default `grep`);
    - `RULE_FILE` (for `ast-grep`/`semgrep`: a committed rule file);
    - `INCLUDE`, `EXCLUDE`;
    - `CLASS=heuristic|correctness` (default `heuristic`);
    - `MESSAGE` (what is wrong) and `FIX` (the right fix, in the repository's terms).
  - **Counting:** per-file match counts over `SCOPE` (or every tracked file under `INCLUDE`), compared with the TSV baseline (`lib/baseline.sh`).
  - **`KEEL_MEASURE=1`** prints baseline rows.
  - **Guidance:** `MESSAGE` and `FIX`, plus "never add a suppression to make this pass".
  - **Engines:** `ast-grep`/`semgrep` are used only when installed (else exit 2 with the reason). Their output is reduced to `path<TAB>count` (`ast-grep scan --json` / `semgrep --json`). Parse it without `jq`, using `grep -o '"file":"[^"]*"'` or the tools' plain-text output modes.
  - **Follow H1's temp-dir rule.**
  - **Guard:** treat a changed `PATTERN`/`RULE_FILE` as a loosening (it changes what is caught). Add it to `guard.sh`'s rule-env comparison, with a test.
  - Commit `feat(keel-harness): generic pattern sensor (grep, ast-grep, semgrep) with baseline`.
- [ ] **Task 3 — `measure.sh pattern <ERE> [pathspec…]`:** a read-only count, files and total, so `rules` can show the as-is state before proposing a pattern rule. Test it. Commit `feat(keel-harness): measure.sh pattern`.
- [ ] **Task 4 — `adopted-patterns` gains the promotion route.** In the catalog, a confirmed pattern with a syntactic form becomes a `pattern.sh` rule. Commit `docs(keel-harness): adopted patterns promote to the pattern sensor`.
- [ ] **Task 5 — master plan:** tick the F3d exemplar and pattern-sensor items, and mark the status row "◐ F3d-1 done". Commit `docs(keel-harness): F3d-1 done`.

## Acceptance

- `pattern.sh` passes the sensor-contract tests (line 1, exit codes, guidance on fail, a baseline that ratchets, skip without its env file).
- `exemplar-missing` has warn and clean tests.
- `guard` flags a changed `PATTERN`.
- `./tests/run.sh` exits 0; `validate --strict` passes; `shellcheck` is clean.
