# keel-harness v0.3 — F3a CI and pre-commit: Implementation Plan

> **For agentic workers:** free; no eval, no model call, no network beyond `git fetch`/`push`. Runs anywhere with bash, git, python3 and `shellcheck`. Steps use checkbox (`- [ ]`) syntax. Copy every file and diff exactly as written here. **Fences:** diffs are fenced with `~~~` because they contain triple backticks; copy what is between the fences.

**Goal:** Close D7 (revised). Today the fast gate reaches only Claude Code, through the Stop hook. Pre-commit and CI must run the **same** `make gate-fast` for every author, human or agent, and CI is the one a local `--no-verify` cannot skip. After F3a:
- `build` proposes two new layers, `ci` and `precommit`, each accepted or declined on its own;
- `harness-check` warns `enforcement-drift` when an installed layer no longer runs the gate;
- a planted defect is red in pre-commit and in CI, and so is a baseline loosened without an ADR (guard).

**Spec:** `docs/specs/2026-10-23-keel-harness-v0.3-design.md` D7 (revised), §5.3. Master plan `docs/plans/2026-10-23-keel-harness-v0.3-plan.md`, phase F3a.

**Design decisions in this plan** (the owner can veto them at review):
1. **CI runs on a clean checkout, so `SCOPE` is the whole repository.** That is stricter than local (every test runs), and keeps `gate.sh` unchanged.
2. **The slow gate is not wired to CI.** Its sensors (mutation, diff coverage) are scoped to changed files, and on a clean checkout they would cover the whole repository. This keeps the README's "never wired to CI" true.
3. **`harness-check` is advisory in CI.** Its `review-due` warning is date-driven and would turn unrelated pull requests red.
4. **`guard` compares with the pull request's target branch** (`KEEL_GUARD_BASE=origin/<base_ref>`, `fetch-depth: 0`). Without that it compares the change with itself and passes every loosening.
5. **Actions are pinned to a commit SHA.** `actions/checkout` v4.3.1 is `34e114876b0b11c390a56381ad16ebd13914f8d5` (`git ls-remote https://github.com/actions/checkout refs/tags/v4.3.1`, a lightweight tag, on 2026-10-28).
6. **Pre-commit uses the hook manager the repository already has, never a new one**: lefthook, pre-commit or husky. A repository with none declines the layer with that reason.
7. **The new `layers` keys are optional.** A state without `ci` or `precommit` is never warned, so `schema_version` stays 3 and existing installs need no upgrade round.

**Provenance:** prototyped on 2026-10-28 on `cdd2c66`.
- `./tests/run.sh` goes from 1031 to **1063** `ok` (with `shellcheck` and PyYAML installed), and `claude plugin validate --strict` passes.
- Applied together with the E2 prototype (`git apply --3way`, no conflict), the suite gives **1112** `ok`.
- The end-to-end tests run the real `gate.sh`, `file-size.sh` and `guard.sh` from the plugin:
  - pre-commit: through a real git hook made from the husky asset;
  - CI: by running the workflow's gate step in a clone of a pull request branch, with `KEEL_GUARD_BASE=origin/main`.
- The workflow itself was not run on GitHub; see Task 4.

## Global constraints

- **Git:**
  1. `git fetch origin claude/harness-engineering-autonomous-agents-d8xhvx`.
  2. Create `feat/keel-harness-v0.3-f3a` from it and push with `-u`.
  3. One commit per task, push after each, no pull request without the owner's approval.
- Installed assets stay bash 3.2 or plain YAML, with no `jq`, no network and no model call.
- Change only what this plan lists. E2 runs in parallel and changes `evals/`, `tests/keel_evals_test.sh` and the README's Evals section; do not touch those.
- `build/SKILL.md` must stay at 250 lines or fewer (`tests/build_test.sh`). This plan brings it to exactly 250.

## Prerequisites

| Tool | Check |
| --- | --- |
| bash, git, python3, `shellcheck` | `./tests/run.sh` exits 0 before you start with **1031** `ok`. If E2 was merged first, expect 1080 before and **1112** at the end |
| PyYAML (optional) | `python3 -c 'import yaml'`; without it the 3 YAML-syntax checks print `skip`, and you get 3 fewer `ok` |

---

## Task 1 — the test first (red)

- [ ] **Step 1:** create `tests/keel_enforcement_test.sh` (executable):

```bash
#!/usr/bin/env bash
# F3a: the CI workflow and pre-commit assets run the same fast gate an agent runs locally.
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
CI="$KEEL/assets/core/ci/keel.yml"
PC="$KEEL/assets/core/precommit"

# --- the assets
[ -f "$CI" ]; check "ci/keel.yml exists" $?
head -1 "$CI" | grep -q '^# Managed by keel-harness'; check "ci/keel.yml carries the managed-by header" $?
grep -q 'keel:repo-specific begin' "$CI" && grep -q 'keel:repo-specific end' "$CI"; check "ci/keel.yml has the repo-specific markers" $?
! grep -E 'uses: ' "$CI" | grep -vqE 'uses: [^@]+@[0-9a-f]{40} '; check "every action is pinned to a full commit SHA" $?
grep -q 'fetch-depth: 0' "$CI"; check "checkout fetches history (guard needs the base)" $?
grep -q "KEEL_GUARD_BASE: .*github.base_ref" "$CI"; check "guard compares with the PR's target branch" $?
grep -q 'run: make gate-fast' "$CI"; check "CI runs make gate-fast" $?
grep -q 'contents: read' "$CI"; check "CI token is read-only" $?
! grep -qE 'CLAUDE|claude ' "$CI"; check "CI calls no model and no plugin path" $?
for f in lefthook.yml pre-commit-config.yaml husky-pre-commit; do
  grep -q 'make gate-fast' "$PC/$f" 2>/dev/null; check "precommit/$f runs make gate-fast" $?
done
# YAML syntax, where PyYAML is installed (it is on GitHub's ubuntu runners)
if python3 -c 'import yaml' 2>/dev/null; then
  for f in "$CI" "$PC/lefthook.yml" "$PC/pre-commit-config.yaml"; do
    python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$f"; check "$(basename "$f") parses as YAML" $?
  done
else
  echo "  skip YAML syntax of the ci and precommit assets (PyYAML not installed)"
fi

# --- a repository with the fast gate, a file-size rule and guard
mkharness() {
  local r; r="$(new_repo)"
  install_asset "$r" assets/core/gate.sh scripts/gate.sh
  install_asset "$r" assets/core/lib/baseline.sh scripts/lib/baseline.sh
  install_asset "$r" assets/core/lib/envparse.sh scripts/lib/envparse.sh
  install_asset "$r" assets/core/sensors/common/guard.sh scripts/sensors/guard.sh
  install_asset "$r" assets/core/sensors/rules/file-size.sh scripts/sensors/file-size.sh
  mkdir -p "$r/.agents/rules" "$r/.agents/baselines" "$r/src"
  cp "$KEEL/assets/core/gate.env" "$r/.agents/gate.env"
  printf "LIMIT=5\nINCLUDE='src'\n" > "$r/.agents/rules/file-size.env"
  printf 'schema_version: 3\nlayers: { ci: installed, precommit: installed }\n' > "$r/.agents/state.yml"
  printf 'gate-fast:\n\t@bash scripts/gate.sh fast\n' > "$r/Makefile"
  printf '.agents/run/\n' > "$r/.gitignore"
  printf '1\n2\n' > "$r/src/a.ts"
  (cd "$r" && git add -A && git commit -q -m harness)
  printf '%s\n' "$r"
}
defect() { printf '1\n2\n3\n4\n5\n6\n7\n' > "$1/src/a.ts"; } # 7 lines, over LIMIT=5

# pre-commit: the husky line as a plain git hook (husky, lefthook and pre-commit all run it)
r="$(mkharness)"
{ printf '#!/usr/bin/env bash\n'; grep -v '^#' "$PC/husky-pre-commit"; } > "$r/.git/hooks/pre-commit"; chmod +x "$r/.git/hooks/pre-commit"
(cd "$r" && printf 'x\n' > src/b.ts && git add src/b.ts && git commit -q -m clean) >/dev/null 2>&1; check "pre-commit: a clean change commits" $?
defect "$r"; (cd "$r" && git add src/a.ts && git commit -q -m defect) >/dev/null 2>&1; [ $? -ne 0 ]; check "pre-commit: a planted defect blocks the commit" $?
(cd "$r" && git log -1 --format=%s) | grep -qx clean; check "pre-commit: the defect was not committed" $?

# CI: the workflow's gate step in a clone of a pull request branch, guard based on origin/main
ci_gate() { # ci_gate ORIGIN BRANCH -> rc of the workflow's gate step
  local c; c="$(mktemp -d)"; _keel_tmps="$_keel_tmps $c"
  git clone -q "$1" "$c/w" 2>/dev/null && (cd "$c/w" && git checkout -q "$2" && KEEL_GUARD_BASE=origin/main make gate-fast >/dev/null 2>&1)
}
r="$(mkharness)"; (cd "$r" && git branch -M main && git checkout -q -b pr && printf 'x\n' > src/b.ts && git add -A && git commit -q -m ok)
ci_gate "$r" pr; check "CI: a clean pull request is green" $?
r="$(mkharness)"; (cd "$r" && git branch -M main && git checkout -q -b pr); defect "$r"; (cd "$r" && git add -A && git commit -q -m defect)
ci_gate "$r" pr; [ $? -ne 0 ]; check "CI: a planted defect is red" $?
r="$(mkharness)"; (cd "$r" && git branch -M main && git checkout -q -b pr); defect "$r"
(cd "$r" && printf '# measured_at: 2026-10-28 review_by: 2027-04-28\nsrc/a.ts\t7\n' > .agents/baselines/file-size.tsv && git add -A && git commit -q -m loosen)
ci_gate "$r" pr; [ $? -ne 0 ]; check "CI: hiding the defect in a baseline without an ADR is red (guard)" $?
finish
```

- [ ] **Step 2:** `bash tests/keel_enforcement_test.sh | grep -c FAIL` is greater than 0: the assets do not exist yet. Do not commit yet.

## Task 2 — the assets (green)

- [ ] **Step 1:** create `plugins/keel-harness/assets/core/ci/keel.yml`:

```yaml
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# keel - the same gate an agent runs locally (make gate-fast), on every pull request. guard compares
# the harness with the pull request's target branch, so a loosening without an ADR fails here too.
# harness-check is advisory: its review-due warning is date-driven and must not fail unrelated PRs.
# The checkout has no uncommitted changes, so SCOPE is the whole repository. The slow gate is not run
# here: its sensors (mutation, diff coverage) are scoped to changed files and would cover everything.
name: keel
on:
  pull_request:
  workflow_dispatch:
permissions:
  contents: read
jobs:
  gate:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
        with:
          fetch-depth: 0
      # --- keel:repo-specific begin ---
      # Toolchain setup copied from this repository's existing workflows (e.g. actions/setup-node).
      # --- keel:repo-specific end ---
      - name: Bootstrap
        run: make bootstrap
      - name: Fast gate
        env:
          KEEL_GUARD_BASE: ${{ github.base_ref && format('origin/{0}', github.base_ref) || '' }}
        run: make gate-fast
      - name: Harness check (advisory)
        run: make harness-check || echo "::warning title=keel harness-check::warnings above; run make harness-check locally"
```

- [ ] **Step 2:** create the three pre-commit snippets in `plugins/keel-harness/assets/core/precommit/`.

  `lefthook.yml`:

```yaml
# keel-harness: merge this entry into lefthook.yml.
pre-commit:
  commands:
    keel-gate:
      run: make gate-fast
```

  `pre-commit-config.yaml`:

```yaml
# keel-harness: merge this entry into .pre-commit-config.yaml.
repos:
  - repo: local
    hooks:
      - id: keel-gate
        name: keel fast gate
        entry: make gate-fast
        language: system
        pass_filenames: false
        always_run: true
```

  `husky-pre-commit`:

```sh
# keel-harness: add this line to .husky/pre-commit.
make gate-fast
```

- [ ] **Step 3: check.**
  - `bash tests/keel_enforcement_test.sh | grep -c FAIL` → 0; it prints 21 `ok` lines (18 without PyYAML).
  - `./tests/run.sh` exits 0.
  - Add `tests/keel_enforcement_test.sh` and the four assets. Commit `feat(keel-harness): CI workflow and pre-commit assets running the fast gate` and push.

## Task 3 — build proposes the layers; harness-check watches them

- [ ] **Step 1:** create `plugins/keel-harness/skills/build/references/enforcement.md`:

```markdown
# Enforcement: the same gate in pre-commit and CI

The Stop hook reaches only Claude Code. Pre-commit and CI run the **same** `make gate-fast` for every
author, human or agent, and CI is the one a local `--no-verify` cannot skip. Each is its own layer in
the proposal (`ci`, `precommit` in `.agents/state.yml`), accepted or declined on its own.

## CI (`ci` layer)

- Copy `${CLAUDE_PLUGIN_ROOT}/assets/core/ci/keel.yml` to `.github/workflows/keel.yml`. Edit only its
  repo-specific block: the toolchain setup steps, copied from the repository's existing workflows
  (`actions/setup-node`, `actions/setup-python`, `actions/setup-java` with the versions they pin).
  No existing workflow and a toolchain to set up → confidence `low`: ask which versions.
- Never edit the gate step, the `KEEL_GUARD_BASE` line or `fetch-depth: 0`: without them `guard`
  compares the pull request with itself and passes every loosening.
- `make harness-check` stays advisory in CI (its `review-due` warning is date-driven).
- CI checks the whole repository (a clean checkout has no `SCOPE`), so it runs every test the local
  gate would skip as unaffected. The slow gate stays local: `make gate-slow` before a pull request.
- Not GitHub (`.gitlab-ci.yml`, `Jenkinsfile`, ...): propose one job with the same three commands
  (`make bootstrap`, `KEEL_GUARD_BASE=<target branch> make gate-fast`, `make harness-check || true`)
  in that system's file, and say it is untested by keel.
- Tell the user to make the `keel` check required in the branch protection; keel cannot set it.

## Pre-commit (`precommit` layer)

Propose the hook manager the repository already uses, never a new one:

| Found | Asset | Merge |
| --- | --- | --- |
| `lefthook.yml` / `.lefthook.yml` | `assets/core/precommit/lefthook.yml` | add the `keel-gate` command under `pre-commit.commands` |
| `.pre-commit-config.yaml` | `assets/core/precommit/pre-commit-config.yaml` | append the `local` repo entry to `repos` |
| `.husky/` | `assets/core/precommit/husky-pre-commit` | append `make gate-fast` to `.husky/pre-commit` |
| none | — | declined: `not_installed: { precommit: "no hook manager in this repository" }` |

Keep every existing entry. The fast gate's budget (`CEILING_SECONDS`) is what a commit waits for; a
budget over 30 s is a reason to decline this layer, and the user decides.

## Verify

- `make harness-check` reports no `enforcement-drift`.
- `.github/workflows/keel.yml` parses as YAML; its gate step is unchanged from the asset.
```

- [ ] **Step 2:** apply this diff from the repository root (save it to a file outside the repository, then `git apply <file>`; if E2 landed first, `git apply --3way <file>`). It changes the README's doctor line, `harness-check.sh` (new check), `build/SKILL.md` (proposal line, state template, self-verify), `doctor/SKILL.md` (fifteen checks) and three test files. Lines in `tests/keel_harness_check_test.sh` contain literal **tab** characters (`'^warn	guard-missing	'`); keep them.

~~~diff
diff --git a/plugins/keel-harness/README.md b/plugins/keel-harness/README.md
--- a/plugins/keel-harness/README.md
+++ b/plugins/keel-harness/README.md
@@ -40,7 +40,7 @@ what the user approved and never migrates production code.
 
 ### `/keel-harness:doctor`
 
-Runs the repository's own validator (`harness-check.sh`, 14 checks), explains each warning and proposes
+Runs the repository's own validator (`harness-check.sh`, 15 checks), explains each warning and proposes
 the fix. Writes nothing.
 
 ## The v0.2 rule
diff --git a/plugins/keel-harness/assets/core/harness-check.sh b/plugins/keel-harness/assets/core/harness-check.sh
--- a/plugins/keel-harness/assets/core/harness-check.sh
+++ b/plugins/keel-harness/assets/core/harness-check.sh
@@ -147,6 +147,27 @@ check_guard_missing() {
   warn guard-missing scripts/sensors/guard.sh "no guard sensor or no scripts/lib/envparse.sh, so the harness can be loosened without anyone noticing" "Run /keel-harness:build to install scripts/sensors/guard.sh and scripts/lib/envparse.sh"
 }
 
+# --- enforcement-drift
+# A ci or precommit layer that state.yml records as installed must still run the same gate.
+check_enforcement_drift() {
+  local f found
+  if grep -qE '(^|[{ ,])ci: *installed' .agents/state.yml; then
+    found=""
+    for f in .github/workflows/*.yml .github/workflows/*.yaml; do
+      [ -f "$f" ] && grep -qE 'make gate-fast|scripts/gate\.sh' "$f" && found=1
+    done
+    [ -n "$found" ] || warn enforcement-drift .github/workflows "the ci layer is installed but no workflow runs make gate-fast, so CI checks something other than the local gate" "Restore .github/workflows/keel.yml with /keel-harness:build, or set ci: not_installed in .agents/state.yml"
+  fi
+  if grep -qE '(^|[{ ,])precommit: *installed' .agents/state.yml; then
+    found=""
+    for f in lefthook.yml .lefthook.yml .pre-commit-config.yaml .husky/pre-commit; do
+      [ -f "$f" ] && grep -qE 'make gate-fast|scripts/gate\.sh' "$f" && found=1
+    done
+    [ -n "$found" ] || warn enforcement-drift .agents/state.yml "the precommit layer is installed but no pre-commit hook runs make gate-fast" "Add the keel-gate entry back with /keel-harness:build, or set precommit: not_installed in .agents/state.yml"
+  fi
+  return 0
+}
+
 # --- sensor-malformed
 check_sensor_malformed() {
   local s name id cls problems
@@ -299,6 +320,7 @@ check_dangling_pointer
 check_hook_missing
 check_run_state
 check_guard_missing
+check_enforcement_drift
 check_sensor_malformed
 check_sensor_unavailable
 check_rule_inconsistent
diff --git a/plugins/keel-harness/skills/build/SKILL.md b/plugins/keel-harness/skills/build/SKILL.md
--- a/plugins/keel-harness/skills/build/SKILL.md
+++ b/plugins/keel-harness/skills/build/SKILL.md
@@ -200,6 +200,7 @@ GATES      fast (budget {{N}}s): typecheck [correctness], lint [heuristic, basel
            tests [correctness], secrets [security], guard [security]; left out: {{sensor}} - measured {{N}}s
            scripts/gate.sh, .agents/gate.env, make gate-fast, make gate-slow
 HOOK       scripts/hooks/claude-stop.sh + a Stop entry in .claude/settings.json (fast gate, timeout 120)
+ENFORCE    ci: .github/workflows/keel.yml; precommit: {{lefthook | pre-commit | husky | none}} (references/enforcement.md)
 ```
 
 **Write nothing before the user accepts.** This rule has no exception. The user's own request can
@@ -217,7 +218,7 @@ schema_version: 3
 installed_at: 2026-10-20          # ISO date, today
 harness_review_by: 2027-04-20     # installed_at + 6 months
 mode: brownfield                  # greenfield | brownfield, confirmed by the user
-layers: { bootstrap: installed, guides: installed, fast_gate: installed, slow_gate: not_installed, hook: installed, rules: not_installed }
+layers: { bootstrap: installed, guides: installed, fast_gate: installed, slow_gate: not_installed, hook: installed, ci: installed, precommit: not_installed, rules: not_installed }
 not_installed:                    # layer or sensor -> the reason, in keel's words
   slow_gate: "no mutation or coverage tool configured"
 ```
@@ -234,7 +235,7 @@ Check what the copied assets do not already guarantee:
 - [ ] `.agents/state.yml` parses as YAML and has `schema_version: 3`; `.gitignore` ignores `.agents/run/`.
 - [ ] `make gate-fast` was actually run and its output read; its verdict line reads
       `gate: fast - ...` and each sensor's `cut -f1` is its own id.
-- [ ] `make harness-check` was run and prints `harness is clean`.
+- [ ] `make harness-check` was run and prints `harness is clean` (no `enforcement-drift`).
 - [ ] Each `heuristic` sensor with a baseline has `.agents/baselines/<id>.tsv` from `KEEL_MEASURE=1`.
 - [ ] A sensor that blew the budget is named, with its seconds, under `not_installed`.
 - [ ] `scripts/` has no `${CLAUDE_*}`, plugin path or `claude` call; `scripts/sensors/guard.sh` and `scripts/lib/envparse.sh` exist.
diff --git a/plugins/keel-harness/skills/doctor/SKILL.md b/plugins/keel-harness/skills/doctor/SKILL.md
--- a/plugins/keel-harness/skills/doctor/SKILL.md
+++ b/plugins/keel-harness/skills/doctor/SKILL.md
@@ -4,7 +4,7 @@ description: >
   Checks whether an installed harness has drifted from the repository it guards, by running the
   same portable validator the repository carries: AGENTS.md over 100 lines, commands cited there
   that no longer resolve, a CLAUDE.md that hides AGENTS.md, dangling rule pointers, a missing Stop
-  hook, misplaced or unignored run state, a missing guard sensor, malformed or unavailable sensors, rules that disagree with their env files, oversize topic
+  hook, misplaced or unignored run state, a missing guard sensor, CI or pre-commit no longer running the gate, malformed or unavailable sensors, rules that disagree with their env files, oversize topic
   files, malformed or stale baselines, and an overdue harness review. Explains each warning and
   proposes the fix; writes nothing. Use when someone asks whether their harness is out of date,
   stale or still valid, or wants a harness health check.
@@ -29,7 +29,7 @@ then `harness-check: N warning(s)` or `harness-check: harness is clean`. Exit 0
 2 no harness: with no `.agents/state.yml`, say so and point at `/keel-harness:build`; that is a
 precondition, not a warning.
 
-## 2. The fourteen checks
+## 2. The fifteen checks
 
 | Check id | Condition | Fix goes through |
 | --- | --- | --- |
@@ -40,6 +40,7 @@ precondition, not a warning.
 | `hook-missing` | no Stop hook pointing at an executable `scripts/hooks/claude-stop.sh` | `build` (hook) |
 | `run-state` | v0.2 run state outside `.agents/run/`, or `.agents/run/` not ignored | `build` (upgrade, section 7b) |
 | `guard-missing` | no `scripts/sensors/guard.sh` or no `scripts/lib/envparse.sh` | `build` (gates) |
+| `enforcement-drift` | the `ci` or `precommit` layer is installed but no workflow or hook runs `make gate-fast` | `build` (`references/enforcement.md`) |
 | `sensor-malformed` | a sensor whose `id=` differs from its file name, whose `class=` is invalid, or that is not executable | edit the file, or `build` |
 | `sensor-unavailable` | a fast sensor exits 2 for a tracked file it covers (tool missing) | `build` (gates) |
 | `rule-inconsistent` | a rule env file is incomplete, points at a missing doc, anchor, sensor or ADR, or its numbers differ from the section | `rules` |
diff --git a/tests/build_test.sh b/tests/build_test.sh
--- a/tests/build_test.sh
+++ b/tests/build_test.sh
@@ -87,4 +87,7 @@ for c in build-python build-java build-react; do
 done
 grep -q 'ruff' "$root/plugins/keel-harness/evals/build-python/graders/lint-is-ruff.md" 2>/dev/null; check "build-python checks that lint uses ruff" $?
 grep -q 'LINT_PATHS' "$root/plugins/keel-harness/evals/build-react/graders/lint-paths.md" 2>/dev/null; check "build-react checks LINT_PATHS" $?
+E="$root/plugins/keel-harness/skills/build/references/enforcement.md"
+has "$S" 'references/enforcement.md'; check "build proposes the ci and precommit layers (F3a)" $?
+for t in 'assets/core/ci/keel.yml' 'KEEL_GUARD_BASE' 'never a new one' 'required'; do has "$E" "$t"; check "enforcement.md: $t" $?; done
 exit $fail
diff --git a/tests/doctor_test.sh b/tests/doctor_test.sh
--- a/tests/doctor_test.sh
+++ b/tests/doctor_test.sh
@@ -14,7 +14,7 @@ has 'prompt-audit'; check "points at /doctor prompt-audit" $?
 grep -qi "writes nothing" "$f"; check "doctor writes nothing" $?
 grep -qi "exactly one warning" "$f"; check "one condition produces one warning" $?
 has 'cmp'; check "proposes updating scripts/harness-check.sh when it differs (cmp)" $?
-for id in agents-size stale-command agents-not-loaded dangling-pointer hook-missing run-state guard-missing sensor-malformed sensor-unavailable \
+for id in agents-size stale-command agents-not-loaded dangling-pointer hook-missing run-state guard-missing enforcement-drift sensor-malformed sensor-unavailable \
           rule-inconsistent topic-size baseline-malformed baseline-stale review-due; do
   has "$id"; check "check id: $id" $?
 done
diff --git a/tests/keel_harness_check_test.sh b/tests/keel_harness_check_test.sh
--- a/tests/keel_harness_check_test.sh
+++ b/tests/keel_harness_check_test.sh
@@ -116,6 +116,13 @@ r="$(mkclean)"; printf 'x\n' > "$r/.agents/last-green"; hc "$r"; only run-state
 r="$(mkclean)"; : > "$r/.gitignore"; commit "$r"; hc "$r"; only run-state .gitignore; check "run-state: .agents/run/ not ignored" $?
 r="$(mkclean)"; mkdir -p "$r/.agents/run"; printf 'x\n' > "$r/.agents/run/last-green"; hc "$r"; [ $rc -eq 0 ]; check "run-state: ignored .agents/run/ is clean" $?
 
+# enforcement-drift
+r="$(mkclean)"; sed -i 's/rules: not_installed }/rules: not_installed, ci: installed }/' "$r/.agents/state.yml"; commit "$r"; hc "$r"; only enforcement-drift .github/workflows; check "enforcement-drift: ci installed, no workflow runs the gate" $?
+r="$(mkclean)"; sed -i 's/rules: not_installed }/rules: not_installed, ci: installed }/' "$r/.agents/state.yml"; mkdir -p "$r/.github/workflows"; cp "$KEEL/assets/core/ci/keel.yml" "$r/.github/workflows/keel.yml"; commit "$r"; hc "$r"; [ $rc -eq 0 ]; check "enforcement-drift: keel.yml installed is clean" $?
+r="$(mkclean)"; sed -i 's/rules: not_installed }/rules: not_installed, precommit: installed }/' "$r/.agents/state.yml"; printf 'pre-commit:\n  commands:\n    lint:\n      run: npx eslint .\n' > "$r/lefthook.yml"; commit "$r"; hc "$r"; only enforcement-drift state.yml; check "enforcement-drift: precommit installed, hook lost the gate" $?
+r="$(mkclean)"; sed -i 's/rules: not_installed }/rules: not_installed, precommit: installed }/' "$r/.agents/state.yml"; cp "$KEEL/assets/core/precommit/lefthook.yml" "$r/lefthook.yml"; commit "$r"; hc "$r"; [ $rc -eq 0 ]; check "enforcement-drift: lefthook entry is clean" $?
+r="$(mkclean)"; sed -i 's/rules: not_installed }/rules: not_installed, ci: not_installed, precommit: not_installed }/' "$r/.agents/state.yml"; commit "$r"; hc "$r"; [ $rc -eq 0 ]; check "enforcement-drift: declined layers are not checked" $?
+
 # guard-missing
 r="$(mkclean)"; rm "$r/scripts/sensors/guard.sh"; commit "$r"; hc "$r"; only guard-missing scripts/sensors/guard.sh; check "guard-missing: no guard sensor" $?
 r="$(mkclean)"; rm "$r/scripts/lib/envparse.sh"; commit "$r"; hc "$r"; printf '%s\n' "$out" | grep -q '^warn	guard-missing	'; check "guard-missing: no envparse lib" $?
~~~

- [ ] **Step 3: check.**
  - `./tests/run.sh` exits 0 with **1063** `ok` (1112 if E2 is merged; 3 fewer without PyYAML). No `FAIL`.
  - `wc -l < plugins/keel-harness/skills/build/SKILL.md` → 250.
  - `shellcheck -S warning plugins/keel-harness/assets/core/harness-check.sh` → nothing at warning level.
  - `claude plugin validate ./plugins/keel-harness --strict` → `Validation passed`. If `claude` is not installed, say so in the report; CI runs it.
  - Commit `feat(keel-harness): build proposes ci and precommit layers; harness-check warns enforcement-drift` and push.

## Task 4 — the workflow on GitHub (owner's call)

The tests prove the gate step's logic, not GitHub's evaluation of the workflow (the `github.base_ref` expression, `fetch-depth: 0` producing `origin/<base>`). Proving it needs a real repository.

- [ ] **Step 1:** ask the owner whether to run it. The options:
  - a throwaway repository where `build` installs `keel.yml`;
  - or nothing, recorded as a gap.

  Do not add `keel.yml` to this repository's own `.github/workflows/`: this repository has no keel harness installed.
- [ ] **Step 2 (only if approved):** in the throwaway repository, open two pull requests and record the run URLs in the report:
  1. one with a planted file-size defect (red at "Fast gate");
  2. one with a clean change (green).

## Task 5 — finish

- [ ] Tick F3a in the master plan's status table: evidence = commits, `ok` count, Task 4 outcome. Commit `docs(keel-harness): tick F3a` and push.
- [ ] Report to the owner:
  - the counts;
  - the Task 4 outcome;
  - every deviation from this plan;
  - which of the design decisions above, if any, you would change, and why.

  Do not open a pull request.
