# keel-harness v0.3 — F1b Measure the tool cases: Implementation Plan

> **For agentic workers:** this plan runs in a **cloud Claude Code session** and spends real money on the owner's account. It has one **hard stop**: before the full run, you send a cost estimate and wait for the owner to approve a ceiling. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Complete the F1 baseline. F1 measured the 5 read-only cases at commit **`cf495ff`** on the owner's machine (`plugins/keel-harness/README.md`, "partial baseline"). The 10 tool cases could not run there: AppArmor blocks the nested `bwrap` sandbox they need. F1b measures those 10 cases at the same commit, in a cloud container where the nested sandbox works.

**Evidence that the host works:** checked on 2026-10-28 in a Claude Code cloud container (Ubuntu 24.04.5):
- after `apt-get install bubblewrap socat`, `bwrap --ro-bind / / bwrap --ro-bind / / true` succeeded;
- `claude auth status` reported `loggedIn: true`;
- OpenJDK 21, node/npm and python3 `venv` were present;
- `registry.npmjs.org`, `pypi.org` and `services.gradle.org` answered 200;
- `repo.maven.apache.org` answered 200 and, once in three tries, **429**.

No eval was run while writing this plan.

**Spec:** `docs/specs/2026-10-23-keel-harness-v0.3-design.md` §2.2 (C9), D31; `docs/plans/2026-10-24-keel-harness-v0.3-f1-plan.md` (F1, whose method this follows).

## Global constraints

- **Money:** nothing beyond the Task 2 smoke run without the owner's written approval of a ceiling; always pass `--max-cost-usd`.
- **Security:** never weaken the sandbox (no `sandbox.enableWeakerNestedSandbox`, no `--dangerously-skip-permissions`). `--trust-plugin` and `--scaffold` run this repository's own scaffolds: allowed because they are the owner's code.
- **Git:** branch `feat/keel-harness-v0.3-f1b`; one commit per task, push after each, no pull request without the owner's approval. Do not change plugin or eval code.
- **No re-runs to chase a number.** Each case runs 3 times per arm. One exception: a case that died before any test body ran, on a network error such as a Maven 429, may be re-run **once**, and the report says so.

## Prerequisites (install in Task 1)

| Tool | Needed by | Check |
| --- | --- | --- |
| `bwrap`, `socat` | Claude Code's Bash sandbox inside the eval sandbox | `bwrap --ro-bind / / bwrap --ro-bind / / true && echo nested-ok` |
| `gitleaks` **≥ 8.19** (`gitleaks dir`) | every case whose harness has `secrets.sh` | `gitleaks version` |
| JDK 17+ | `build-java`, `rules-architecture-java` | `java -version` |
| node + npm | TypeScript/React cases, rules cases | `node --version; npm --version` |
| python3 `venv` | `build-python` | `python3 -m venv --help >/dev/null && echo ok` |
| `claude`, logged in | everything | `claude --version; claude auth status` |

Ubuntu's `gitleaks` package is 8.16 and lacks `gitleaks dir`, so do not use it.

---

## Task 1 — prepare and qualify the host (free)

- [ ] **Step 1: branch.**
  1. `git fetch origin claude/harness-engineering-autonomous-agents-d8xhvx`.
  2. Create `feat/keel-harness-v0.3-f1b` from it and push with `-u`.
- [ ] **Step 2: pinned worktree.**
  1. `git worktree add ../keel-f1b-measure cf495ff`.
  2. `git -C ../keel-f1b-measure log --oneline -1`. Expected: `cf495ff docs(keel-harness): F0 done`.
  3. Eval commands run from `../keel-f1b-measure/plugins/keel-harness`.
- [ ] **Step 3: sandbox tools.** `apt-get install -y bubblewrap socat`, then the nested check from the table → `nested-ok`. If it fails, **hard stop** and report the error line.
- [ ] **Step 4: gitleaks from the official release, checksum-verified.** Downloading and running a binary may need the owner's permission in your session. If it is denied, stop and ask; do not work around it.

```bash
V=8.24.2; d=$(mktemp -d); cd "$d"
curl -fsSLO "https://github.com/gitleaks/gitleaks/releases/download/v$V/gitleaks_${V}_linux_x64.tar.gz"
curl -fsSLO "https://github.com/gitleaks/gitleaks/releases/download/v$V/gitleaks_${V}_checksums.txt"
grep " gitleaks_${V}_linux_x64.tar.gz\$" "gitleaks_${V}_checksums.txt" | sha256sum -c -   # must print: OK
tar -xzf "gitleaks_${V}_linux_x64.tar.gz" gitleaks && install -m 0755 gitleaks /usr/local/bin/gitleaks
gitleaks version   # 8.24.2
```

- [ ] **Step 5: the rest.** Run every check in the table and write down the results. Also run `claude plugin validate ./plugins/keel-harness --strict` from the worktree root → `Validation passed`, and note `claude --version`.

## Task 2 — smoke run and cost estimate

- [ ] **Step 1: one tool case, one run per arm,** from `../keel-f1b-measure/plugins/keel-harness`:

```bash
claude plugin eval . --case gate-catches-defect --runs 1 --scaffold --trust-plugin \
  --allow-tools Write Edit Bash --no-publish --max-cost-usd 5 --json ../../../f1b-smoke.json
```

  Qualification: in the WITH arm the case must write `gate-output.txt`, and no run may fail with `apply-seccomp` / `setgroups … Permission denied`. If either fails, **hard stop**: v0.1 hit exactly this (README), so report it and do not tune settings.
- [ ] **Step 2: estimate.**
  1. Take the smoke run's `costUsd`: the top-level field in `f1b-smoke.json`, or the sum of its runs' `costUsd`.
  2. Per-run cost × 3 runs × 2 arms × 10 cases, plus 30 % margin.
  3. Split that into two ceilings, one per invocation in Task 3 (`--tag build`: 5 cases; `--tag rules`: 5 cases), weighted by any difference you expect. Java cases run Gradle and are slower.
- [ ] **Step 3: HARD STOP.** Send the owner:
  - the smoke result and cost;
  - the estimate;
  - the two proposed ceilings.

  Wait for written approval.

## Task 3 — full run (after approval)

`--case` keeps only its last value when repeated (checked on 2.1.310), so the 10 cases run as two tag groups. Under `with-without`, the `rules-effect-*` pair is compared by each case's WITH arm.

- [ ] **Step 1: build group.** It covers `build-typescript`, `build-react`, `build-python`, `build-java` and `gate-catches-defect`.

```bash
claude plugin eval . --tag build --runs 3 --scaffold --trust-plugin --allow-tools Write Edit Bash \
  --no-publish --max-cost-usd <BUILD_CEILING> --json ../../../f1b-build.json
```

- [ ] **Step 2: rules group.** It covers `rules-brownfield`, `rules-greenfield`, `rules-architecture-java`, `rules-effect-with` and `rules-effect-without`.

```bash
claude plugin eval . --tag rules --runs 3 --scaffold --trust-plugin --allow-tools Write Edit Bash \
  --no-publish --max-cost-usd <RULES_CEILING> --json ../../../f1b-rules.json
```

  Exit codes:
  - **2:** the ceiling was hit; stop and report partial results.
  - **1:** some case scored below 1.0; that is data.
  - **A Java run that failed on a Maven 429** before any test body ran may be re-run once (Global constraints).
- [ ] **Step 3: raw results.**
  1. Copy `f1b-*.json` and each run's `aggregate-result.json` (under `evals/results/<timestamp>/`) into `docs/evals/keel-v0.3-f0/` on your branch.
  2. Commit `docs(keel-harness): F1b raw eval results at cf495ff (tool cases)` and push.

## Task 4 — record and report

- [ ] **Step 1: README.** In `plugins/keel-harness/README.md`, fill the 10 `host-blocked` rows using the F1 columns `WITH | W-OUT | Δ | Verdict | Cost (USD)`.
  - In the notes above the table: change "partial baseline" to "baseline", add a line for this host (cloud container, OS, Claude Code version, date), and add the F1b total spent.
  - Keep the F1 lines.
- [ ] **Step 2: findings.** Under the existing findings, add one paragraph per tool case with Δ ≤ 0, with a WITH score below 1.0, or with a confounder: network failures, a Maven 429, a run that hit `max_turns`, a re-run. The existence floor still needs three consecutive sessions; name candidates only.
  - For the `rules-effect` pair, state which case's WITH arm scored higher. That pair is the only test of whether approved rules help an agent.
- [ ] **Step 3: tick** the F1 checkboxes that F1b completes in `docs/plans/2026-10-23-keel-harness-v0.3-plan.md`. Commit `docs(keel-harness): F1b complete the eval baseline at cf495ff` and push.
- [ ] **Step 4: report to the owner:**
  - the 10 new rows;
  - the total spent against the approved ceilings;
  - every re-run and why;
  - any deviation from this plan.

  Remove the worktree (`git worktree remove ../keel-f1b-measure`). Do not open a pull request.
