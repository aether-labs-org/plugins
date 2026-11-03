# keel-harness v0.3 — E1 Doctor evals: Implementation Plan

> **For agentic workers:** Task 1 is free and runs anywhere. Task 2 spends money and needs a host where Claude Code's nested Bash sandbox works (a cloud Claude Code session works; see the F1b plan). Steps use checkbox (`- [ ]`) syntax. Copy every file and diff **verbatim**.

**Goal:** Make the two `doctor` eval cases measure what the skill does. F1 found two problems (`plugins/keel-harness/README.md`, F1 findings):
1. The `doctor-*` cases allow only `[Read, Glob, Grep, Skill]`, but the skill's first step runs the validator through Bash. The WITH arm never ran `harness-check.sh`.
2. `doctor-agents-not-loaded` scored 1.00 in both arms, because a model without the plugin already knows the `@AGENTS.md` bridge. The validator's own test already covers that check.

E1 grants `Bash` to both cases. It replaces `doctor-agents-not-loaded` with `doctor-validator-drift`, which tests what only the plugin's `doctor` adds: the repository carries an **older** `harness-check.sh` that misses a condition, here a missing guard sensor, and only the plugin's current validator finds it. Then it measures both cases.

**Provenance:** prototyped on 2026-10-28 on `c97cbc8`:
- `./tests/run.sh` gives 1020 → **1023** `ok` and `claude plugin validate --strict` passes;
- the new scaffold was run (with network, without `gitleaks`): `make harness-check` (the repository's copy) reported `dangling-pointer` and `sensor-unavailable` but **no** guard problem, while the plugin's `assets/core/harness-check.sh` also reported `guard-missing`.

That is the separation the case relies on. No eval was run.

## Global constraints

- Git:
  1. `git fetch origin claude/harness-engineering-autonomous-agents-d8xhvx`.
  2. Create `feat/keel-harness-v0.3-e1` from it and push with `-u`.
  3. One commit per task, push after each, no pull request without the owner's approval.
- Change only what this plan lists. Do not touch plugin skills or assets.
- **Money (Task 2):** run only with an approved ceiling; this plan proposes **USD 8**. F1 spent USD 3.03 on the two old `doctor-*` cases, and Bash adds turns. Never weaken the sandbox.

## Prerequisites

| Tool | Needed by | Check |
| --- | --- | --- |
| bash, git, `jq`, `shellcheck` | Task 1 | `./tests/run.sh` exits 0 before you start (1020 `ok`; 1028 if F2b was merged first, then expect 1031 at the end and apply the diffs with `git apply --3way`) |
| node + npm, network | Task 1 Step 4, Task 2 (scaffolds run `npm install`) | `npm --version` |
| nested Bash sandbox, `gitleaks` ≥ 8.19, `claude` logged in | Task 2 | see `docs/plans/2026-10-28-keel-harness-v0.3-f1b-plan.md` Task 1 |

---

## Task 1 — the two cases

- [ ] **Step 1: retire and rename.** First delete the two graders that tested the bridge, then rename the case (in this order: `git rm` refuses a path whose rename is already staged):

```bash
git rm -q plugins/keel-harness/evals/doctor-agents-not-loaded/graders/names-claude-md.md \
          plugins/keel-harness/evals/doctor-agents-not-loaded/graders/names-the-bridge.md
git mv plugins/keel-harness/evals/doctor-agents-not-loaded plugins/keel-harness/evals/doctor-validator-drift
```

- [ ] **Step 2: write the new case files.**

  `plugins/keel-harness/evals/doctor-validator-drift/case.yaml`:

```yaml
schema_version: "1.1"
name: doctor-validator-drift
description: The repository carries an older harness-check.sh that misses a condition (no guard sensor); doctor runs the plugin's own validator, names the missing guard and the validator drift, and writes nothing.
tags: [doctor, drift]
context:
  scaffold_script: scaffold.sh
```

  `plugins/keel-harness/evals/doctor-validator-drift/prompt.md`:

```markdown
---
max_turns: 30
allowed_tools: [Read, Glob, Grep, Skill, Bash]
---

Is the agent harness in this repository still up to date?
```

  `plugins/keel-harness/evals/doctor-validator-drift/scaffold.sh` (keep it executable):

```bash
#!/usr/bin/env bash
# The doctor-finds-drift repository (TypeScript repo + harness fixture + AGENTS.md) with the AGENTS.md
# size drift removed, then: the guard sensor is missing, and the repository's own harness-check.sh is
# an older copy that has no guard-missing check, so `make harness-check` reports a clean harness.
# Only the plugin's current validator finds it - that is what doctor adds over the repository's copy.
# Host prerequisite: gitleaks installed (otherwise secrets also reports sensor-unavailable).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$here/../doctor-finds-drift/scaffold.sh"
# drop the 120 filler lines appended by doctor-finds-drift
sed -i '/^- filler pointer line$/d' AGENTS.md
rm scripts/sensors/guard.sh
sed '/^check_guard_missing$/d' "$here/../../assets/core/harness-check.sh" > scripts/harness-check.sh
chmod +x scripts/harness-check.sh
printf '\nharness-check:\n\t@bash scripts/harness-check.sh\n' >> Makefile
git add -A && git -c user.email=eval@local -c user.name=eval commit -qm "older validator, no guard sensor"
```

  `plugins/keel-harness/evals/doctor-validator-drift/graders/names-guard.md`:

```markdown
---
type: regex
pattern: 'guard[\s\S]{0,200}(missing|absent|not installed|install|no )'
flags: i
target: last_message
weight: 2
---
```

  `plugins/keel-harness/evals/doctor-validator-drift/graders/names-validator-drift.md`:

```markdown
---
type: regex
pattern: 'harness-check[\s\S]{0,300}(differ|older|out of date|outdated|stale|behind|update)'
flags: i
target: last_message
weight: 2
---
```

  `graders/writes-nothing.md` stays unchanged.
- [ ] **Step 3: grant Bash to `doctor-finds-drift`; update the structural test and the README.**

```diff
diff --git a/plugins/keel-harness/evals/doctor-finds-drift/prompt.md b/plugins/keel-harness/evals/doctor-finds-drift/prompt.md
index 6ff3ebb..d4e11f0 100644
--- a/plugins/keel-harness/evals/doctor-finds-drift/prompt.md
+++ b/plugins/keel-harness/evals/doctor-finds-drift/prompt.md
@@ -1,6 +1,6 @@
 ---
-max_turns: 20
-allowed_tools: [Read, Glob, Grep, Skill]
+max_turns: 30
+allowed_tools: [Read, Glob, Grep, Skill, Bash]
 ---
 
 Is the agent harness in this repository still up to date?
```

```diff
diff --git a/tests/doctor_test.sh b/tests/doctor_test.sh
index 742b170..53eb856 100755
--- a/tests/doctor_test.sh
+++ b/tests/doctor_test.sh
@@ -19,9 +19,11 @@ for id in agents-size stale-command agents-not-loaded dangling-pointer hook-miss
   has "$id"; check "check id: $id" $?
 done
 ! grep -qi "capture rate" "$f"; check "no history-dependent checks" $?
-ev="$root/plugins/keel-harness/evals/doctor-agents-not-loaded"
-for x in case.yaml prompt.md scaffold.sh; do [ -f "$ev/$x" ]; check "doctor-agents-not-loaded has $x" $?; done
-[ "$(ls "$ev/graders" 2>/dev/null | wc -l)" -ge 2 ]; check "doctor-agents-not-loaded has graders" $?
-bash -n "$ev/scaffold.sh" 2>/dev/null; check "doctor-agents-not-loaded scaffold parses" $?
+ev="$root/plugins/keel-harness/evals/doctor-validator-drift"
+for x in case.yaml prompt.md scaffold.sh; do [ -f "$ev/$x" ]; check "doctor-validator-drift has $x" $?; done
+[ "$(ls "$ev/graders" 2>/dev/null | wc -l)" -ge 3 ]; check "doctor-validator-drift has graders" $?
+bash -n "$ev/scaffold.sh" 2>/dev/null; check "doctor-validator-drift scaffold parses" $?
+[ ! -e "$root/plugins/keel-harness/evals/doctor-agents-not-loaded" ]; check "doctor-agents-not-loaded retired (E1)" $?
+for c in doctor-finds-drift doctor-validator-drift; do grep -q "allowed_tools: \[.*Bash" "$root/plugins/keel-harness/evals/$c/prompt.md"; check "$c grants Bash (doctor runs the validator)" $?; done
 ! grep -rq 'sensors:' "$root/plugins/keel-harness/evals/gate-catches-defect/fixtures/harness/.agents/state.yml"; check "eval fixture state has no sensors list" $?
 exit $fail
```

```diff
diff --git a/plugins/keel-harness/README.md b/plugins/keel-harness/README.md
index 0eb3f0b..a514e7d 100644
--- a/plugins/keel-harness/README.md
+++ b/plugins/keel-harness/README.md
@@ -87,7 +87,7 @@ Run `claude plugin eval . --scaffold` from `plugins/keel-harness/`. Host prerequ
 | `build-python` | python3 with `venv`, network |
 | `build-java`, `rules-architecture-java` | JDK 17+, network (Gradle wrapper) |
 | `rules-greenfield` | none beyond the tool allow-list |
-| `doctor-finds-drift`, `doctor-agents-not-loaded` | node/npm, network, `gitleaks` (exactly one warning) |
+| `doctor-finds-drift`, `doctor-validator-drift` | node/npm, network, `gitleaks`; `--allow-tools Bash` (the doctor skill runs the validator) |
 
 v0.2 numbers, **partial baseline**: 5 of the 15 cases measured (the read-only ones). `rules-effect-with`
 and `rules-effect-without` are meant to run with `--ablation none` and be compared by hand, since that
@@ -124,7 +124,7 @@ have not run.
 | `rules-architecture-java` | not run | | | host-blocked (nested bwrap) | |
 | `rules-effect-with` / `-without` | not run | | | host-blocked (nested bwrap) | |
 | `doctor-finds-drift` | 1.00 | 0.33 | +0.67 | pass | 1.52 |
-| `doctor-agents-not-loaded` | 1.00 | 1.00 | 0.00 | Δ 0, see findings | 1.51 |
+| `doctor-agents-not-loaded` | 1.00 | 1.00 | 0.00 | retired in E1, see findings | 1.51 |
 
 ### Findings (partial baseline at `cf495ff`)
 
@@ -138,6 +138,15 @@ not separate the two arms in this measurement. It is a candidate for the existen
 delete after three consecutive runs with Δ ≤ 0); this is one measurement session, and nothing is deleted
 in F1.
 
+**E1 (2026-10-28): `doctor-agents-not-loaded` retired, `doctor-validator-drift` added.** A model without
+the plugin already knows the `@AGENTS.md` bridge, and `harness-check.sh`'s `agents-not-loaded` check is
+covered by `tests/keel_harness_check_test.sh`. The new case tests what only the plugin's `doctor` adds:
+the repository carries an older `harness-check.sh` that has no `guard-missing` check and reports no
+guard problem, the guard sensor is missing, and only the plugin's current validator names it. Both
+`doctor-*` cases now grant `Bash`, which the skill needs to run the validator: F1's `doctor-*` runs
+could not run it. The scaffold's AGENTS.md also points at `dist/`, which the scaffold never builds, so
+`dangling-pointer` is an extra warning in both cases; the graders do not count warnings.
+
 No case scored below 1.0 in the WITH arm. In the W-OUT arm the failing graders were: `rubric-axes` and
 `rubric-states` (`assess-mature-repo`), `context-partial` (`assess-claude-md`), `names-the-drift`
 (`doctor-finds-drift`), each in all 3 runs.
```

- [ ] **Step 4: verify.**
  - `./tests/run.sh; echo rc=$?` → `rc=0`, **1023** `ok`.
  - `claude plugin validate ./plugins/keel-harness --strict` → `Validation passed`.
  - Premise check, in a scratch directory (needs network for `npm install`):

```bash
d=$(mktemp -d) && cd "$d" && bash <repo>/plugins/keel-harness/evals/doctor-validator-drift/scaffold.sh
make harness-check | grep -c guard-missing                                        # 0: the repository's copy misses it
bash <repo>/plugins/keel-harness/assets/core/harness-check.sh | grep -c guard-missing   # 1: the plugin's copy finds it
```

- [ ] **Step 5: commit and push.** `test(keel-harness): doctor evals grant Bash; replace doctor-agents-not-loaded with doctor-validator-drift (E1)`

## Task 2 — measure both cases (paid; nested-sandbox host)

- [ ] **Step 1: approval.** Confirm the owner approved the ceiling (USD 8 unless they set another). If not, ask and wait.
- [ ] **Step 2: run at your branch head**, from `plugins/keel-harness`:

```bash
claude plugin eval . --tag doctor --runs 3 --scaffold --trust-plugin --allow-tools Bash \
  --no-publish --max-cost-usd 8 --json ../../e1-doctor.json
```

  Exit codes:
  - **2:** the ceiling was hit; stop and report.
  - **1:** a score is below 1.0; that is data.
  - **Any run failing with `apply-seccomp` / `setgroups`:** the host is blocked; stop and report.
- [ ] **Step 3: record.**
  1. Copy `e1-doctor.json` and the run's `aggregate-result.json` to `docs/evals/keel-v0.3-e1/`.
  2. In `plugins/keel-harness/README.md`, add one row for `doctor-validator-drift` under the F1 table, with columns `WITH | W-OUT | Δ | Verdict | Cost (USD)`.
  3. Add a note under the E1 paragraph with the new `doctor-finds-drift` numbers. They are not comparable to F1's row, because Bash is now granted; say so.
  4. Say whether `doctor-validator-drift` separates the arms. If its Δ ≤ 0, report it; do not tune graders to make it pass.
- [ ] **Step 4: commit and push.** `docs(keel-harness): E1 doctor eval results`. Then report to the owner:
  - the two rows;
  - the cost;
  - any deviation from this plan.

  Do not open a pull request.
