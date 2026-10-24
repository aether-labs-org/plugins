# keel-harness v0.3 — F1 Measure: Implementation Plan

> **For agentic workers:** this plan runs on the **owner's machine** and spends real money. Follow it step by step. It has two **hard stops** where you wait for the owner: before the full run (budget) and if the host cannot run the cases. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Measure keel-harness as it stands at the end of F0, commit **`cf495ff`**: every eval case, with and without the plugin, including cost. The numbers become the ruler for F2 onward: a later phase may not make a case worse (master plan, F1 and F2 acceptance).

**Why a fixed commit:** F2a moves files in parallel. Measuring `cf495ff` keeps the baseline stable whatever lands on other branches.

**Spec:** `docs/specs/2026-10-23-keel-harness-v0.3-design.md` §2.2 (C9) and D31. Read `plugins/keel-harness/README.md`, sections "Evals" and "v0.1 eval baseline", before Task 1: they document the host problem v0.1 hit.

**Provenance:** the commands below were checked against `claude plugin eval --help` on Claude Code 2.1.310. No case was run while writing this plan: the paid runs are the point of F1.

## Global constraints

- **Money:** never start a paid run beyond Task 2 without the owner's written approval of a ceiling, and always pass `--max-cost-usd` with that ceiling.
- **Security:** `--trust-plugin` and `--scaffold` run this repository's own scaffolds as you; they are this owner's code, which is why they are allowed here. Never pass `sandbox.enableWeakerNestedSandbox` or any setting that weakens the sandbox. If the host blocks the sandbox, stop (Task 1).
- **Git:** results go to the branch `feat/keel-harness-v0.3-f1`; commit once per task, push after each commit, no pull request without the owner's approval. Do not change plugin code.
- **No re-runs to chase a number.** A case runs 3 times per arm; report what came out.

## Prerequisites

| Tool | Needed by | Check |
| --- | --- | --- |
| `claude` CLI, logged in | everything | `claude --version` |
| git | everything | `git --version` |
| node + npm, network | `build-typescript`, `build-react`, `gate-catches-defect`, `rules-*`, `doctor-*` | `node --version; npm --version` |
| `gitleaks` | cases whose harness has `secrets.sh`; the `doctor-*` cases expect exactly one warning only when it is installed | `gitleaks version` |
| python3 with `venv`, network | `build-python` | `python3 -m venv --help >/dev/null && echo ok` |
| JDK 17+, network (Gradle wrapper) | `build-java`, `rules-architecture-java` | `java -version` |
| **Linux only:** `bwrap`, `socat`, nested unprivileged user namespaces | Claude Code's Bash sandbox inside the eval sandbox | `bwrap --ro-bind / / bwrap --ro-bind / / true && echo nested-ok` |

On macOS the sandbox does not use `bwrap`; skip the last row.

---

## Task 1 — prepare and qualify the host (free)

- [ ] **Step 1: branch.**
  1. `git fetch origin claude/harness-engineering-autonomous-agents-d8xhvx`.
  2. Create `feat/keel-harness-v0.3-f1` from it and push with `-u`.
- [ ] **Step 2: pinned worktree.**
  1. `git worktree add ../keel-f1-measure cf495ff`.
  2. `cd ../keel-f1-measure && git log --oneline -1`. Expected: `cf495ff docs(keel-harness): F0 done`.
  3. All eval commands run from `../keel-f1-measure/plugins/keel-harness`.
- [ ] **Step 3: prerequisites.** Run every check in the table and write down the results; they go in the report. A missing tool for a case means that case is reported `not run (missing <tool>)`. Install it only if the owner agrees.
- [ ] **Step 4: plugin loads.** `claude plugin validate ./plugins/keel-harness --strict` (from the worktree root) → `Validation passed`. Then `claude --version` and note the version.
- [ ] **Step 5: sandbox (Linux).**
  - If the nested `bwrap` check fails with `setgroups … Permission denied`, the host cannot run the Bash cases; v0.1 hit exactly this (README).
  - **Hard stop:** report it with the error line and the value of `/proc/sys/kernel/apparmor_restrict_unprivileged_userns` if the file exists.
  - Do not change kernel settings and do not weaken the sandbox.

Nothing to commit in Task 1 unless you wrote notes; keep them for the report.

## Task 2 — smoke run and cost estimate (the only paid step before approval)

- [ ] **Step 1: read-only case**, from `../keel-f1-measure/plugins/keel-harness`:

```bash
claude plugin eval . --case should-not-trigger --runs 1 --trust-plugin --no-publish \
  --max-cost-usd 2 --json ../../../f1-smoke-1.json
```

- [ ] **Step 2: tool-heavy case:**

```bash
claude plugin eval . --case gate-catches-defect --runs 1 --scaffold --trust-plugin \
  --allow-tools Write Edit Bash --no-publish --max-cost-usd 5 --json ../../../f1-smoke-2.json
```

  Qualification: the case writes `gate-output.txt`. If Bash calls fail with `apply-seccomp` / `setgroups … Permission denied`, the host is blocked; hard stop, as in Task 1 Step 5.
- [ ] **Step 3: estimate.**
  1. Read the cost of each smoke run from the command's summary or the `--json` file. Search it for `cost`, and say which field you used.
  2. Estimate the full run: (cost of a read-only run × 3 runs × 2 arms × 5 read-only cases) + (cost of a tool run × 3 × 2 × 10 tool cases).
  3. Add 30 % margin.
  - Read-only cases: `assess-mature-repo`, `assess-claude-md`, `should-not-trigger`, `doctor-finds-drift`, `doctor-agents-not-loaded`.
  - Tool cases: `build-typescript`, `build-react`, `build-python`, `build-java`, `gate-catches-defect`, `rules-brownfield`, `rules-greenfield`, `rules-architecture-java`, `rules-effect-with`, `rules-effect-without`.
- [ ] **Step 4: HARD STOP.** Send the owner:
  - the two smoke costs;
  - the estimate and the proposed `--max-cost-usd`;
  - the cases you will skip for missing tools.

  Wait for written approval of a ceiling. Do not continue without it.

## Task 3 — full run (after approval)

All 15 cases in **one** invocation, so one ceiling covers everything. `--case` cannot select several cases: repeating it keeps only the last one (checked on 2.1.310 with no-match globs). Under `with-without`, the `rules-effect-with` / `rules-effect-without` pair also gets no-plugin arms. The README's hand comparison uses each case's WITH arm.

- [ ] **Step 1:**

```bash
claude plugin eval . --runs 3 --scaffold --trust-plugin --allow-tools Write Edit Bash \
  --no-publish --max-cost-usd <APPROVED> --json ../../../f1-full.json
```

  Exit 2 means the ceiling was hit: stop and report the partial results. Exit 1 only means some case scored below 1.0 (the default `--threshold`); that is data, not an error.
- [ ] **Step 2: keep the raw results.**
  1. Copy `f1-smoke-*.json`, `f1-full.json` and each run's `aggregate-result.json` (under `evals/results/<timestamp>/`, which git ignores) to `docs/evals/keel-v0.3-f0/` on the `feat/keel-harness-v0.3-f1` branch, in the main checkout, not the pinned worktree.
  2. Commit with `docs(keel-harness): F1 raw eval results at cf495ff` and push.

## Task 4 — record the baseline

- [ ] **Step 1: README table.** In `plugins/keel-harness/README.md` on the F1 branch, replace the v0.2 table's `not run` rows with the measured values:
  - columns `WITH | W-OUT | Δ | Verdict`, plus a new `Cost (USD)` column;
  - above the table, add the date, `Claude Code <version>`, `measured at cf495ff`, host OS, and the cases not run with the reason;
  - for the pair, fill both rows as usual; the verdict compares `rules-effect-with` WITH against `rules-effect-without` WITH (the only test of whether approved rules help an agent).
- [ ] **Step 2: findings.** Under the table, one short paragraph per case with Δ ≤ 0, per case that scored below 1.0 in the WITH arm, and per confounder you saw (as v0.1 did for `build-typescript`). The v0.2 existence floor applies: a case is rewritten or deleted only after **three consecutive runs** with Δ ≤ 0. Name the candidates; do not delete anything in F1.
- [ ] **Step 3: tick F1** in `docs/plans/2026-10-23-keel-harness-v0.3-plan.md`. Commit `docs(keel-harness): F1 eval baseline at cf495ff` and push.
- [ ] **Step 4: report to the owner:**
  - the README table;
  - the total spent against the ceiling;
  - the skipped cases and why;
  - every deviation from this plan.

  Then remove the worktree with `git worktree remove ../keel-f1-measure`. Do not open a pull request.
