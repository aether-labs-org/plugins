# keel-harness v0.3 — E3 Tool cases on the owner's machine: Implementation Plan

> **For agentic workers:** this plan runs on the **owner's Linux machine** and spends real money. It has three **hard stops** where you wait for the owner: before changing AppArmor, before the full run (budget), and if the host still cannot run the cases. **Every `sudo` command is run by the owner, not by you**: print it, wait until the owner says it ran, then check its effect. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Measure the 10 eval cases that need tools. Today no measurement shows whether keel's core helps an agent: `build-*`, `gate-catches-defect`, `rules-*`, and the `rules-effect` pair, which is the only test of whether approved rules improve the result (D49). D50 replaces D49 with this run.

**Why it failed before:**

| Run | Host | What blocked it |
| --- | --- | --- |
| F1 | owner's machine, Ubuntu 26.04 | AppArmor (`kernel.apparmor_restrict_unprivileged_userns=1`) stops `bwrap` from creating a user namespace inside another one. Claude Code's Bash sandbox needs that nested `bwrap` inside the eval's sandbox (`bwrap: No permissions to create a new namespace`). |
| F1b | cloud container, running as root | The workspace was mounted read-only. |

**The fix and what it costs:**
- A narrow AppArmor profile lets **only** `/usr/bin/bwrap` create user namespaces, for the duration of the run. Then it is removed.
- Ubuntu documents this pattern: a per-binary profile with `userns`, instead of turning the restriction off globally. Canonical's discussion: [Understanding AppArmor User Namespace Restriction](https://discourse.ubuntu.com/t/understanding-apparmor-user-namespace-restriction/58007).
- The cost: while the profile is loaded, any local user can use `bwrap` to create user namespaces, as on Ubuntu before 23.10. The global `sysctl` switch is **not** used, because it would lift the restriction for every program.

**Hypothesis, not fact:** that this profile is enough for Claude Code's nested sandbox. No one has run it on this host yet. Task 1 tests it before anything is paid, and stops if it fails.

**Spec:** `docs/specs/2026-10-23-keel-harness-v0.3-design.md` §2.2 (C9), D31, D50. Master plan: phase E3. **Depends on E2** (grant groups and tool lists), merged into `claude/harness-engineering-autonomous-agents-d8xhvx`.

## Global constraints

- **Money:** never start a run beyond the smoke run (Task 2) without the owner's written approval of a ceiling, and always pass `--max-cost-usd`.
- **Security:**
  - `--trust-plugin` and `--scaffold` run this repository's own scaffolds as you; they are this owner's code.
  - Never pass `sandbox.enableWeakerNestedSandbox` or any setting that weakens the sandbox.
  - Never change the AppArmor `sysctl`.
  - The AppArmor profile is removed in Task 5 even if a run fails or the owner stops the plan.
- **Git:**
  1. Results go to `feat/keel-harness-v0.3-e3`, created from `claude/harness-engineering-autonomous-agents-d8xhvx` after E2 is merged, and pushed with `-u`.
  2. One commit per task, push after each, no pull request without the owner's approval.
  3. No plugin code changes.
- **No re-runs to chase a number.** Each case runs 3 times per arm; report what came out.

## Prerequisites

| Tool | Needed by | Check |
| --- | --- | --- |
| `claude` CLI, logged in | everything | `claude --version` |
| node + npm, network | `build-typescript`, `build-react`, `gate-catches-defect`, `rules-*` | `node --version; npm --version` |
| python3 with `venv`, network | `build-python` | `python3 -m venv --help >/dev/null && echo ok` |
| JDK 17+, network (Gradle wrapper) | `build-java`, `rules-architecture-java` | `java -version` |
| `gitleaks` ≥ 8.19 | harnesses with `secrets.sh` | `gitleaks version` |
| `bwrap`, `socat` | Claude Code's Bash sandbox | `command -v bwrap socat` |
| `apparmor_parser`, `aa-status` | Task 1 | `command -v apparmor_parser aa-status` |

A missing tool for a case means that case is reported `not run (missing <tool>)`. Install it only if the owner agrees.

---

## Task 1 — qualify the host (free)

- [ ] **Step 1: pinned worktree.**
  1. `git fetch origin claude/harness-engineering-autonomous-agents-d8xhvx`.
  2. Note the head commit `<C>` and check that it contains `tests/keel_evals_test.sh` (E2).
  3. `git worktree add ../keel-e3-measure <C>`. All eval commands run from `../keel-e3-measure/plugins/keel-harness`.
- [ ] **Step 2: reproduce the block.**

```bash
cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns      # expected: 1
command -v bwrap                                                # expected: /usr/bin/bwrap
bwrap --ro-bind / / bwrap --ro-bind / / true && echo nested-ok  # expected: fails, as in F1
sudo aa-status 2>/dev/null | grep -i bwrap; ls /etc/apparmor.d | grep -i bwrap
```

  - If the nested check already prints `nested-ok`, skip to Task 2: no profile is needed.
  - If `bwrap` is not `/usr/bin/bwrap`, use its real path (`readlink -f "$(command -v bwrap)"`) in the profile below.
  - **HARD STOP if an AppArmor profile already attaches to that path** (for example Ubuntu's `bwrap-userns-restrict`). Two profiles on one binary is not something this plan has tested. Report the `aa-status` lines and the file names, and wait.
- [ ] **Step 3: HARD STOP — the owner approves the profile.** Show the owner the profile and its cost (the "fix and what it costs" paragraph above), and wait for a yes.

```text
# /etc/apparmor.d/keel-eval-bwrap
# Temporary: lets /usr/bin/bwrap create user namespaces for Claude Code's sandbox during keel evals.
# Remove after the run: keel-harness E3 plan, Task 5.
abi <abi/4.0>,
include <tunables/global>

profile keel-eval-bwrap /usr/bin/bwrap flags=(unconfined) {
  userns,
}
```

  The owner installs it with:

```bash
sudo install -m 0644 /dev/stdin /etc/apparmor.d/keel-eval-bwrap <<'EOF'
# Temporary: lets /usr/bin/bwrap create user namespaces for Claude Code's sandbox during keel evals.
# Remove after the run: keel-harness E3 plan, Task 5.
abi <abi/4.0>,
include <tunables/global>

profile keel-eval-bwrap /usr/bin/bwrap flags=(unconfined) {
  userns,
}
EOF
sudo apparmor_parser -r /etc/apparmor.d/keel-eval-bwrap
```

- [ ] **Step 4: check the effect** (you run these, no `sudo`):

```bash
bwrap --ro-bind / / bwrap --ro-bind / / true && echo nested-ok
d="$(mktemp -d)"; bwrap --ro-bind / / --bind "$d" "$d" bwrap --ro-bind / / --bind "$d" "$d" touch "$d/w" && ls "$d/w" && echo nested-write-ok
```

  - Both lines print their `-ok`: go on.
  - Otherwise **HARD STOP:** report the error lines, then go to Task 5 (remove the profile).
- [ ] **Step 5: plugin loads.** From the worktree root:
  1. `claude plugin validate ./plugins/keel-harness --strict` → `Validation passed`.
  2. Note `claude --version`, the OS (`lsb_release -ds`) and the kernel (`uname -r`).

Nothing to commit in Task 1; keep the notes for the report.

## Task 2 — smoke runs (the only paid step before approval)

From `../keel-e3-measure/plugins/keel-harness`. `--case` takes a single glob here, which is fine for one case.

- [ ] **Step 1:**

```bash
claude plugin eval . --case gate-catches-defect --runs 1 --scaffold --trust-plugin \
  --allow-tools Bash Write Edit --no-publish --max-cost-usd 2 --json ../../../e3-smoke-1.json
claude plugin eval . --case build-typescript --runs 1 --scaffold --trust-plugin \
  --allow-tools Bash Write Edit --no-publish --max-cost-usd 4 --json ../../../e3-smoke-2.json
```

- [ ] **Step 2: qualification.**
  - In `gate-catches-defect`, the agent wrote `gate-output.txt` and the `gate-failed` grader passed in the WITH arm.
  - No Bash call failed with `Read-only file system`, `apply-seccomp`, `setgroups` or `No permissions to create a new namespace`. Search the JSON for each string.
  - The progress output shows no `not granted` tool.

  If any of these fails, **HARD STOP**: report the excerpt, then go to Task 5.
- [ ] **Step 3: estimate.**
  1. Read each smoke run's cost from the JSON (`costUsd`; say which field you used).
  2. Estimate:
     - the `tools` group: 8 cases × 3 runs × 2 arms × the mean smoke cost per run;
     - plus the `effect` group: 2 cases × 3 runs × 1 arm (it runs with `--ablation none`);
     - plus 30 % margin.
  3. `build-java` and `rules-architecture-java` download Gradle and are slower. If their cost differs, say so instead of hiding it in the mean.
- [ ] **Step 4: HARD STOP.** Send the owner:
  - both smoke costs;
  - the estimate;
  - the proposed ceiling for each group;
  - any case you will skip for a missing tool.

  Wait for written approval.

## Task 3 — measured runs (after approval)

- [ ] **Step 1:**

```bash
claude plugin eval . --tag tools --scaffold --trust-plugin --allow-tools Bash Write Edit \
  --no-publish --max-cost-usd <TOOLS> --json ../../../e3-tools.json
claude plugin eval . --tag effect --scaffold --trust-plugin --allow-tools Bash Write Edit \
  --ablation none --no-publish --max-cost-usd <EFFECT> --json ../../../e3-effect.json
```

  - Exit 2 = ceiling hit: stop, report the partial results, and still do Task 5.
  - Exit 1 = some case below 1.0; that is data.
- [ ] **Step 2: keep the raw results.**
  1. Copy the four JSON files and each run's `aggregate-result.json` (under `evals/results/<timestamp>/`) to `docs/evals/keel-v0.3-e3/` on `feat/keel-harness-v0.3-e3`, in the main checkout, not the worktree.
  2. Commit `docs(keel-harness): E3 raw eval results at <C>` and push.

## Task 4 — record

- [ ] **Step 1: README.**
  - In `plugins/keel-harness/README.md`, add **"E3 results"** after the E2 results.
  - Above the table: the date, `Claude Code <version>`, `measured at <C>`, the host OS and kernel, "nested sandbox through the temporary `keel-eval-bwrap` AppArmor profile", and the total spent against the ceilings.
  - Table columns: `Case | WITH | W-OUT | Δ | Verdict | Cost (USD)`.
  - For the `effect` pair, give each case's single-arm score. The verdict compares `rules-effect-with` against `rules-effect-without`: a higher `with` score means approved rules helped.
- [ ] **Step 2: findings.** One short paragraph for each of these:
  - each case with Δ ≤ 0;
  - each case below 1.0 in the WITH arm;
  - each confounder you saw.

  The v0.2 existence floor applies: a case is rewritten or deleted only after three consecutive runs with Δ ≤ 0. Name the candidates; delete nothing.
- [ ] **Step 3:** remove the `not run` sentences about the 10 tool cases from the README's F1 section, and point to E3 instead.
- [ ] **Step 4:** tick E3 in the master plan's status table. Commit `docs(keel-harness): E3 tool-case results` and push.

## Task 5 — restore the host (always, even after a stop)

- [ ] **Step 1:** the owner runs:

```bash
sudo apparmor_parser -R /etc/apparmor.d/keel-eval-bwrap
sudo rm /etc/apparmor.d/keel-eval-bwrap
```

- [ ] **Step 2:** check that the block is back: `bwrap --ro-bind / / bwrap --ro-bind / / true` fails again, and `cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns` prints `1`.
- [ ] **Step 3:** `git worktree remove ../keel-e3-measure`.
- [ ] **Step 4:** report to the owner:
  - the README table and findings;
  - the total spent;
  - the Task 5 check output;
  - every deviation from this plan.

  Do not open a pull request.
