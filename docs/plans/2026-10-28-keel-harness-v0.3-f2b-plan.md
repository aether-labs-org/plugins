# keel-harness v0.3 — F2b State and ADR folder: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or superpowers:subagent-driven-development) to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax. Copy every diff **verbatim**.

**Goal:** Three behaviour changes from the v0.3 spec, all deterministic:
1. **Run state in `.agents/run/` (D39).** Logs, fingerprints and the lock move out of the root of `.agents/`. A repository then ignores one line, `.agents/run/`, instead of seven, and keel never touches `.agents/skills/` or `.agents/plugins/`, which belong to other tools. `harness-check` gains a 14th check, `run-state`, which flags v0.2 run state left behind and an `.agents/run/` that is not ignored.
2. **ADR folder (D45).** `rules` detects an existing ADR folder (`docs/adr/`, `doc/adr/`, `docs/decisions/`, `docs/architecture/decisions/`, in that order) or creates `docs/adr/`, and records it as `adr_dir:` in `.agents/state.yml`. `guard` counts only ADRs in that folder when it is set, and the sensors' guidance names it instead of a fixed path.
3. **`schema_version: 3`** with an upgrade round for v0.2 installs in `build` §7b.

**Out of scope (moved to F2c):** `scripts/keel` with phases. It is built together with the skill rewrite that calls it. The master plan says so.

**Spec:** `docs/specs/2026-10-23-keel-harness-v0.3-design.md` D39, D40 (plans stay ignored until F3b), D45.

**Provenance:** prototyped on 2026-10-28 on `c97cbc8` (F2a done) and run:
- `./tests/run.sh` goes from 1020 to **1028** `ok`, exit 0, and `claude plugin validate --strict` passes;
- with only the test diff applied, exactly the 18 checks listed in Task 1 fail;
- the end-to-end check in Task 2 Step 3 produced the outputs written there.

`skills/build/SKILL.md` ends at 249 of its 250 allowed lines. If a step's output differs, stop and report.

## Global constraints

- Git:
  1. `git fetch origin claude/harness-engineering-autonomous-agents-d8xhvx`.
  2. Create `feat/keel-harness-v0.3-f2b` from it and push with `-u`.
  3. Commit once, at the end of Task 2, then push; no pull request without the owner's approval.
- Installed scripts stay bash 3.2-compatible, no `jq`, no plugin paths (`tests/keel_assets_test.sh` enforces this).
- Do not bump the plugin version. Do not start F2c.

## Prerequisites

`bash`, `git`, `jq`, `shellcheck`, `claude` (as in the F2a plan). Before Task 1: `./tests/run.sh` exits 0 with **1020** `ok` on your branch. If the E1 branch was merged first, expect 1023 here and 1031 at the end, and apply each diff with `git apply --3way` (both touch `tests/doctor_test.sh` and the plugin README; the combination was checked). Any other count means stop.

---

## Task 1 — tests first

- [ ] **Step 1: apply the test diff:**

```diff
diff --git a/tests/build_test.sh b/tests/build_test.sh
index 1213b25..10bfe92 100755
--- a/tests/build_test.sh
+++ b/tests/build_test.sh
@@ -60,8 +60,8 @@ has "$S" '@AGENTS.md' && has "$S" '.claude/CLAUDE.md'; check "SKILL.md has the C
 CE="$sk/references/context-engineering.md"
 ! has "$CE" '150–200'; check "context-engineering drops the unsourced instruction count" $?
 has "$CE" '2602.11988'; check "context-engineering cites arXiv 2602.11988" $?
-# guard.sh only reads ADR folders (D45); keel writes ADRs to docs/decisions/ until F2.
-! grep -rq --exclude=guard.sh 'docs/adr' "$root/plugins/keel-harness"; check "docs/adr appears nowhere in the plugin (guard.sh reads it)" $?
+has "$S" '.agents/run/'; check "build ignores .agents/run/" $?
+has "$S" 'schema_version: 3'; check "build writes schema_version: 3" $?
 g="$root/plugins/keel-harness/evals/build-typescript/graders"
 [ -f "$g/claude-md-import.md" ] && [ -f "$g/linecount-measured.md" ]; check "claude-md-import and linecount-measured graders exist" $?
 ! grep -q "PreToolUse" "$S"; check "SKILL.md installs no blocking hook" $?
diff --git a/tests/doctor_test.sh b/tests/doctor_test.sh
index 742b170..b4e8b9e 100755
--- a/tests/doctor_test.sh
+++ b/tests/doctor_test.sh
@@ -14,7 +14,7 @@ has 'prompt-audit'; check "points at /doctor prompt-audit" $?
 grep -qi "writes nothing" "$f"; check "doctor writes nothing" $?
 grep -qi "exactly one warning" "$f"; check "one condition produces one warning" $?
 has 'cmp'; check "proposes updating scripts/harness-check.sh when it differs (cmp)" $?
-for id in agents-size stale-command agents-not-loaded dangling-pointer hook-missing guard-missing sensor-malformed sensor-unavailable \
+for id in agents-size stale-command agents-not-loaded dangling-pointer hook-missing run-state guard-missing sensor-malformed sensor-unavailable \
           rule-inconsistent topic-size baseline-malformed baseline-stale review-due; do
   has "$id"; check "check id: $id" $?
 done
diff --git a/tests/keel_gate_test.sh b/tests/keel_gate_test.sh
index f97b09d..be7c396 100644
--- a/tests/keel_gate_test.sh
+++ b/tests/keel_gate_test.sh
@@ -72,7 +72,7 @@ stub_sensor "$r" scripts/sensors/slow/s.sh s correctness pass "slow one" 0
 out="$(cd "$r" && bash scripts/gate.sh slow 2>&1)"; rc=$?
 [ $rc -eq 0 ] && printf '%s\n' "$out" | grep -qE 'gate: slow - PASSED \(1 of 1\) \| ceiling 600s'; check "slow verdict and ceiling" $?
 [ ! -e "$r/.marker_fast" ]; check "slow does not run fast sensors" $?
-[ -f "$r/.agents/last-run-slow.log" ]; check "slow log written" $?
+[ -f "$r/.agents/run/last-run-slow.log" ]; check "slow log written" $?
 (cd "$r" && bash scripts/gate.sh bogus >/dev/null 2>&1); [ $? -eq 64 ]; check "bogus mode rc 64" $?
 (cd /tmp && bash "$r/scripts/gate.sh" >/dev/null 2>&1); [ $? -eq 0 ]; check "runs from any cwd" $?
 
@@ -80,7 +80,7 @@ out="$(cd "$r" && bash scripts/gate.sh slow 2>&1)"; rc=$?
 r="$(mkrepo)"
 echo 1 > "$r/x.ts"; echo 1 > "$r/z.ts"; (cd "$r" && git add x.ts z.ts && git commit -q -m x)
 rm "$r/x.ts"; echo 2 > "$r/y.ts"; echo 2 >> "$r/z.ts"; echo 3 > "$r/my file ação.ts"
-mkdir -p "$r/.agents/.gate-lock"; echo f > "$r/.agents/last-seen"; echo f > "$r/.agents/last-fail"; echo n > "$r/.agents/notes.md"
+mkdir -p "$r/.agents/run/.gate-lock"; echo f > "$r/.agents/run/last-seen"; echo f > "$r/.agents/run/last-fail"; echo n > "$r/.agents/notes.md"
 stub_sensor "$r" scripts/sensors/a.sh a correctness pass "ok" 0 "printf '%s\\n' \"\$SCOPE\" > \"\$PWD/scope.out\""
 (cd "$r" && bash scripts/gate.sh >/dev/null 2>&1)
 grep -qx 'y.ts' "$r/scope.out" && grep -qx 'z.ts' "$r/scope.out" && ! grep -qx 'x.ts' "$r/scope.out"; check "SCOPE excludes deleted, includes untracked" $?
@@ -98,5 +98,5 @@ out="$(cd "$r" && bash scripts/gate.sh 2>&1)"; rc=$?
 r="$(mkrepo)"
 stub_sensor "$r" scripts/sensors/a.sh a correctness fail "many" 1 "for i in \$(seq 1 60); do echo \"  line \$i\"; done"
 out="$(cd "$r" && bash scripts/gate.sh 2>&1)"
-[ "$(printf '%s\n' "$out" | tail -1)" = "output truncated at 40 lines - full log in .agents/last-run.log" ]; check "truncation notice" $?
+[ "$(printf '%s\n' "$out" | tail -1)" = "output truncated at 40 lines - full log in .agents/run/last-run.log" ]; check "truncation notice" $?
 finish
diff --git a/tests/keel_guard_test.sh b/tests/keel_guard_test.sh
index 83ce415..0b565a5 100755
--- a/tests/keel_guard_test.sh
+++ b/tests/keel_guard_test.sh
@@ -67,6 +67,14 @@ run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | grep -qF 'CEILING_SECONDS raised
 r="$(mk)"; mkdir -p "$r/scripts/sensors/disabled"; (cd "$r" && git mv scripts/sensors/file-size.sh scripts/sensors/disabled/file-size.sh)
 run "$r"; [ $rc -eq 1 ] && printf '%s' "$out" | grep -qF 'scripts/sensors/file-size.sh: sensor removed or disabled'; check "disabling a sensor fails" $?
 
+# adr_dir in state.yml (D45): only that folder's ADRs count
+r="$(mk)"; printf 'adr_dir: docs/decisions\n' >> "$r/.agents/state.yml"; mkdir -p "$r/docs/decisions"; (cd "$r" && git add -A && git commit -q -m adr-dir)
+sed -i.bak 's/LIMIT=10/LIMIT=50/' "$r/.agents/rules/file-size.env"; rm -f "$r/.agents/rules/file-size.env.bak"
+printf 'Raise .agents/rules/file-size.env\n' > "$r/docs/adr/0009-raise.md"
+run "$r"; [ $rc -eq 1 ]; check "adr_dir: an ADR outside the recorded folder does not count" $?
+mv "$r/docs/adr/0009-raise.md" "$r/docs/decisions/0009-raise.md"
+run "$r"; [ $rc -eq 0 ]; check "adr_dir: an ADR in the recorded folder counts" $?
+
 # committed loosening is still caught against the merge-base with origin/HEAD
 r="$(mk)"; (cd "$r" && git update-ref refs/remotes/origin/main HEAD && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main)
 sed -i.bak 's/LIMIT=10/LIMIT=99/' "$r/.agents/rules/file-size.env"; rm -f "$r/.agents/rules/file-size.env.bak"; (cd "$r" && git commit -qam loosen)
diff --git a/tests/keel_harness_check_test.sh b/tests/keel_harness_check_test.sh
index 653367d..1598ab3 100644
--- a/tests/keel_harness_check_test.sh
+++ b/tests/keel_harness_check_test.sh
@@ -16,6 +16,7 @@ mkclean() {
   mkdir -p "$r/.agents/baselines" "$r/.agents/rules" "$r/.claude" "$r/docs/decisions" "$r/scripts/sensors/slow" "$r/src"
   cp "$KEEL/assets/core/gate.env" "$r/.agents/gate.env"
   cp "$KEEL/assets/adapters/claude/settings-stop.json" "$r/.claude/settings.json"
+  printf '.agents/run/\n' > "$r/.gitignore"
   cat > "$r/Makefile" <<'MK'
 bootstrap:
 	npm install
@@ -110,6 +111,11 @@ r="$(mkclean)"; chmod -x "$r/scripts/hooks/claude-stop.sh"; hc "$r"; only hook-m
 r="$(mkclean)"; printf '{ "hooks": { "PostToolUse": [] } }\n' > "$r/.claude/settings.json"; hc "$r"; only hook-missing settings.json; check "hook-missing: no Stop entry" $?
 r="$(mkclean)"; sed -i 's/hook: installed/hook: not_installed/' "$r/.agents/state.yml"; rm "$r/.claude/settings.json"; hc "$r"; [ $rc -eq 0 ]; check "hook-missing: skipped when the hook layer was declined" $?
 
+# run-state
+r="$(mkclean)"; printf 'x\n' > "$r/.agents/last-green"; hc "$r"; only run-state .agents; check "run-state: v0.2 run state outside .agents/run/" $?
+r="$(mkclean)"; : > "$r/.gitignore"; commit "$r"; hc "$r"; only run-state .gitignore; check "run-state: .agents/run/ not ignored" $?
+r="$(mkclean)"; mkdir -p "$r/.agents/run"; printf 'x\n' > "$r/.agents/run/last-green"; hc "$r"; [ $rc -eq 0 ]; check "run-state: ignored .agents/run/ is clean" $?
+
 # guard-missing
 r="$(mkclean)"; rm "$r/scripts/sensors/guard.sh"; commit "$r"; hc "$r"; only guard-missing scripts/sensors/guard.sh; check "guard-missing: no guard sensor" $?
 r="$(mkclean)"; rm "$r/scripts/lib/envparse.sh"; commit "$r"; hc "$r"; printf '%s\n' "$out" | grep -q '^warn	guard-missing	'; check "guard-missing: no envparse lib" $?
@@ -191,5 +197,5 @@ rm -f "$r/scope.seen"
 # README.agents.md
 G="$KEEL/assets/core/README.agents.md"
 [ -f "$G" ] && [ "$(wc -l < "$G")" -le 120 ]; check "README.agents.md exists and is at most 120 lines" $?
-for t in 'make harness-check' 'scripts/sensors/disabled/' 'KEEL_MEASURE=1' 'docs/decisions/' '.claude/settings.json' 'scripts/sensors/'; do grep -qF -- "$t" "$G" 2>/dev/null; check "README.agents.md mentions $t" $?; done
+for t in 'make harness-check' 'scripts/sensors/disabled/' 'KEEL_MEASURE=1' 'adr_dir' '.claude/settings.json' 'scripts/sensors/'; do grep -qF -- "$t" "$G" 2>/dev/null; check "README.agents.md mentions $t" $?; done
 finish
diff --git a/tests/keel_python_sensors_test.sh b/tests/keel_python_sensors_test.sh
index e729351..6e017e8 100644
--- a/tests/keel_python_sensors_test.sh
+++ b/tests/keel_python_sensors_test.sh
@@ -56,5 +56,5 @@ printf '%s\n' "$out" | head -1 | grep -q '^tests	correctness	pass	3 passed in 0.
 : > "$r/stub.log"; run "$r" tests SCOPE=tests/unit/test_mod.py; grep -q 'tests/unit/test_mod.py' "$r/stub.log"; check "tests: changed test file runs itself" $?
 : > "$r/stub.log"; run "$r" tests; [ -s "$r/stub.log" ] && ! grep -q 'test_mod' "$r/stub.log"; check "tests: empty SCOPE -> whole suite" $?
 run "$r" tests SCOPE=pkg/mod.py STUB_EXIT=1 STUB_OUT=$'FAILED tests/unit/test_mod.py::test_x - assert 1 == 2\n1 failed, 2 passed in 0.2s'
-[ $rc -eq 1 ] && printf '%s\n' "$out" | grep -q '^  FAILED tests/unit/test_mod.py' && printf '%s\n' "$out" | grep -q '^  guidance: .*docs/decisions/'; check "tests fail + guidance" $?
+[ $rc -eq 1 ] && printf '%s\n' "$out" | grep -q '^  FAILED tests/unit/test_mod.py' && printf '%s\n' "$out" | grep -q '^  guidance: .*adr_dir'; check "tests fail + guidance" $?
 finish
diff --git a/tests/keel_stop_hook_test.sh b/tests/keel_stop_hook_test.sh
index 194a432..6a98d5f 100644
--- a/tests/keel_stop_hook_test.sh
+++ b/tests/keel_stop_hook_test.sh
@@ -45,13 +45,13 @@ r="$(mkrepo --no-commit)"; echo a > "$r/u.txt"; g1="$(cd "$r" && tree_fingerprin
 
 # --- skip when equal to last-green
 r="$(mkrepo)"; echo a > "$r/t.txt"; rm -f "$W/ran"
-(cd "$r" && tree_fingerprint > .agents/last-green)
+(cd "$r" && mkdir -p .agents/run && tree_fingerprint > .agents/run/last-green)
 hook "$r" '{}'; [ -z "$out" ] && [ $rc -eq 0 ] && [ "$(ran)" = 0 ]; check "fingerprint == last-green: silent, gate not run" $?
 
 # --- pass
 r="$(mkrepo)"; echo a > "$r/t.txt"; rm -f "$W/ran"
 hook "$r" '{}' STUB_RC=0
-[ -z "$out" ] && [ $rc -eq 0 ] && [ -s "$r/.agents/last-green" ] && [ "$(ran)" = 1 ]; check "pass: silent, last-green written" $?
+[ -z "$out" ] && [ $rc -eq 0 ] && [ -s "$r/.agents/run/last-green" ] && [ "$(ran)" = 1 ]; check "pass: silent, last-green written" $?
 hook "$r" '{}' STUB_RC=0; [ "$(ran)" = 1 ]; check "second run on same tree skips the gate" $?
 
 # --- fail
@@ -68,7 +68,7 @@ assert c.startswith("keel gate failed after your changes. Fix each failing senso
 assert "guidance:" in c
 assert "decision" not in d
 '; check "fail: valid Stop JSON with header and guidance" $?
-[ ! -e "$r/.agents/last-green" ]; check "fail: last-green not written" $?
+[ ! -e "$r/.agents/run/last-green" ]; check "fail: last-green not written" $?
 
 # --- loop guard
 echo b >> "$r/t.txt"
@@ -103,12 +103,12 @@ assert d["systemMessage"] == "keel gate could not run (scripts/gate.sh exited 12
 '; check "gate crash -> systemMessage" $?
 
 # --- lock
-r="$(mkrepo)"; echo a > "$r/t.txt"; rm -f "$W/ran"; mkdir -p "$r/.agents/.gate-lock"
+r="$(mkrepo)"; echo a > "$r/t.txt"; rm -f "$W/ran"; mkdir -p "$r/.agents/run/.gate-lock"
 hook "$r" '{}' STUB_RC=1 STUB_OUT_FILE="$FAILOUT"
 [ -z "$out" ] && [ "$(ran)" = 0 ]; check "fresh lock: silent, gate not run" $?
-touch -d '20 minutes ago' "$r/.agents/.gate-lock"
+touch -d '20 minutes ago' "$r/.agents/run/.gate-lock"
 hook "$r" '{}' STUB_RC=1 STUB_OUT_FILE="$FAILOUT"
-[ -n "$out" ] && [ "$(ran)" = 1 ] && [ ! -d "$r/.agents/.gate-lock" ]; check "stale lock: removed, gate runs, lock released" $?
+[ -n "$out" ] && [ "$(ran)" = 1 ] && [ ! -d "$r/.agents/run/.gate-lock" ]; check "stale lock: removed, gate runs, lock released" $?
 
 # --- no changes (RF5)
 r="$(mkrepo)"; rm -f "$W/ran"; (cd "$r" && git add -A && git commit -q -m h)
@@ -118,7 +118,7 @@ hook "$r" '{}' STUB_RC=1 STUB_OUT_FILE="$FAILOUT"
 # --- a commit made during the turn is still checked
 r="$(mkrepo)"; echo a > "$r/t.txt"; (cd "$r" && git add -A && git commit -q -m a); rm -f "$W/ran"
 hook "$r" '{}' STUB_RC=1 STUB_OUT_FILE="$FAILOUT"
-[ -z "$out" ] && [ "$(ran)" = 0 ] && [ -s "$r/.agents/last-seen" ]; check "first look at a clean tree: recorded, silent, gate not run" $?
+[ -z "$out" ] && [ "$(ran)" = 0 ] && [ -s "$r/.agents/run/last-seen" ]; check "first look at a clean tree: recorded, silent, gate not run" $?
 fa="$(cd "$r" && tree_fingerprint)"; echo b >> "$r/t.txt"; (cd "$r" && git commit -q -am b); fb="$(cd "$r" && tree_fingerprint)"
 [ "$fa" != "$fb" ]; check "fingerprint changes after a commit (clean tree, new HEAD)" $?
 hook "$r" '{}' STUB_RC=1 STUB_OUT_FILE="$FAILOUT"
@@ -136,7 +136,7 @@ out="$(cd "$d" && printf '{}' | GATE_RAN="$W/ran" bash scripts/hooks/claude-stop
 # --- never exit 2
 r="$(mkrepo)"; echo z > "$r/t.txt"
 for rcv in 0 1 2 5 127; do
-  rm -rf "$r/.agents/last-green" "$r/.agents/last-fail" "$r/.agents/last-seen"
+  rm -rf "$r/.agents/run/last-green" "$r/.agents/run/last-fail" "$r/.agents/run/last-seen"
   hook "$r" '{}' STUB_RC=$rcv STUB_OUT_FILE="$FAILOUT"; [ $rc -eq 0 ]; check "gate rc $rcv -> hook rc 0" $?
 done
 
diff --git a/tests/keel_ts_sensors_test.sh b/tests/keel_ts_sensors_test.sh
index 52e4021..8a8677f 100644
--- a/tests/keel_ts_sensors_test.sh
+++ b/tests/keel_ts_sensors_test.sh
@@ -79,7 +79,7 @@ run "$r" tests SCOPE=src/a.ts STUB_OUT="      Tests  3 passed (3)"
 printf '%s\n' "$out" | head -1 | grep -q '^tests	correctness	pass	Tests  3 passed (3)$'; check "tests pass line 1" $?
 : > "$r/stub.log"; run "$r" tests; grep -qx 'run' "$r/stub.log"; check "tests empty SCOPE -> run" $?
 run "$r" tests SCOPE=src/a.ts STUB_EXIT=1 STUB_OUT=$'      Tests  1 failed (1)\n FAIL  src/a.test.ts > x\nAssertionError: expected 1 to be 2'
-[ $rc -eq 1 ] && printf '%s\n' "$out" | grep -q '^  guidance: .*docs/decisions/'; check "tests fail + guidance cites docs/decisions" $?
+[ $rc -eq 1 ] && printf '%s\n' "$out" | grep -q '^  guidance: .*adr_dir'; check "tests fail + guidance cites adr_dir" $?
 r2="$(mk)"; use_stub "$r2" jest node_modules/.bin/jest; echo 1 > "$r2/src/a.ts"
 sed -i 's/^RUNNER="vitest"/RUNNER="jest"/; s#node_modules/.bin/vitest#node_modules/.bin/jest#' "$r2/scripts/sensors/tests.sh"
 run "$r2" tests SCOPE=src/a.ts; grep -qx -- '--passWithNoTests --findRelatedTests src/a.ts' "$r2/stub.log"; check "tests jest findRelatedTests, passing when no test is related" $?
diff --git a/tests/rules_test.sh b/tests/rules_test.sh
index 3808dcd..e4d1da8 100644
--- a/tests/rules_test.sh
+++ b/tests/rules_test.sh
@@ -42,7 +42,8 @@ has "$R/plan-template.md" 'review_by' && has "$R/plan-template.md" 'make gate-fa
 [ -f "$R/nested-agents-md-template.md" ] && has "$R/nested-agents-md-template.md" '## Rules' && has "$R/nested-agents-md-template.md" '100 lines'; check "nested-agents-md-template.md" $?
 [ -f "$R/interview.md" ] && has "$R/interview.md" 'at most 4 questions'; check "interview.md" $?
 has "$sk/../build/SKILL.md" '/keel-harness:rules'; check "build SKILL.md offers /keel-harness:rules" $?
-! grep -rq --exclude=guard.sh 'docs/adr' "$root/plugins/keel-harness"; check "docs/adr appears nowhere (guard.sh reads it)" $?
+has "$sk/SKILL.md" 'adr_dir:'; check "rules records adr_dir in state.yml (D45)" $?
+has "$sk/SKILL.md" 'docs/adr/'; check "rules defaults the ADR folder to docs/adr/" $?
 ! grep -rq "docs/""rules" "$root/plugins" "$root/tests"; check "per-rule doc path is gone (D28)" $?
 
 # --- Task 17: rules evals
```

- [ ] **Step 2: run.** `./tests/run.sh > /tmp/f2b-red.log; grep FAIL /tmp/f2b-red.log | sed 's/^ *//' | sort -u`. Expected, exactly these 18 lines:

```text
FAIL README.agents.md mentions adr_dir
FAIL adr_dir: an ADR outside the recorded folder does not count
FAIL build ignores .agents/run/
FAIL build writes schema_version: 3
FAIL check id: run-state
FAIL fingerprint == last-green: silent, gate not run
FAIL first look at a clean tree: recorded, silent, gate not run
FAIL fresh lock: silent, gate not run
FAIL pass: silent, last-green written
FAIL rules defaults the ADR folder to docs/adr/
FAIL rules records adr_dir in state.yml (D45)
FAIL run-state: .agents/run/ not ignored
FAIL run-state: v0.2 run state outside .agents/run/
FAIL slow log written
FAIL stale lock: removed, gate runs, lock released
FAIL tests fail + guidance
FAIL tests fail + guidance cites adr_dir
FAIL truncation notice
```

  Do not commit yet.

## Task 2 — implementation

- [ ] **Step 1: apply the plugin diff:**

```diff
diff --git a/plugins/keel-harness/README.md b/plugins/keel-harness/README.md
index 0eb3f0b..593dfe8 100644
--- a/plugins/keel-harness/README.md
+++ b/plugins/keel-harness/README.md
@@ -35,12 +35,12 @@ what the user approved and never migrates production code.
 
 - **Reads:** the code (read-only measurements), instruction files, existing ADRs
 - **Writes:** rule sections in `docs/architecture.md`, `docs/conventions.md`, `docs/testing.md`;
-  `docs/decisions/` ADRs; `.agents/rules/<id>.env`; rule sensors, baselines and generated tool config
+  ADRs in the repository's ADR folder (`docs/adr/` by default); `.agents/rules/<id>.env`; rule sensors, baselines and generated tool config
   (ArchUnit test, `.dependency-cruiser.cjs`, `.importlinter`); local plans in `.agents/plans/`
 
 ### `/keel-harness:doctor`
 
-Runs the repository's own validator (`harness-check.sh`, 13 checks), explains each warning and proposes
+Runs the repository's own validator (`harness-check.sh`, 14 checks), explains each warning and proposes
 the fix. Writes nothing.
 
 ## The v0.2 rule
diff --git a/plugins/keel-harness/assets/adapters/claude/claude-stop.sh b/plugins/keel-harness/assets/adapters/claude/claude-stop.sh
index 3bce9aa..324150d 100755
--- a/plugins/keel-harness/assets/adapters/claude/claude-stop.sh
+++ b/plugins/keel-harness/assets/adapters/claude/claude-stop.sh
@@ -33,7 +33,7 @@ tree_fingerprint() {
     git rev-parse -q --verify HEAD 2>/dev/null
     git diff HEAD --binary 2>/dev/null || git diff --cached --binary 2>/dev/null
     git ls-files --others --exclude-standard -z 2>/dev/null | while IFS= read -r -d '' f; do
-      case "$f" in .agents/last-green | .agents/last-seen | .agents/last-fail | .agents/last-run*.log | .agents/.gate-lock/*) continue ;; esac
+      case "$f" in .agents/run/* | .agents/last-green | .agents/last-seen | .agents/last-fail | .agents/last-run*.log | .agents/.gate-lock/*) continue ;; esac
       printf '%s %s\n' "$f" "$(git hash-object -- "$f" 2>/dev/null)"
     done
   } | git hash-object --stdin
@@ -53,27 +53,27 @@ _claude_stop_main() {
   input="$(cat)"
   cd "$(dirname "$0")/../.." || return 0
   git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
-  mkdir -p .agents
+  mkdir -p .agents/run
   printf '%s' "$input" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && active=1
 
-  # .agents/last-green: the tree the gate last passed on. .agents/last-seen: the tree the hook last
+  # .agents/run/last-green: the tree the gate last passed on. .agents/run/last-seen: the tree the hook last
   # looked at, whatever the result. Both include HEAD, so a commit made this turn is a change.
   fp="$(tree_fingerprint)"
-  if [ -f .agents/last-green ] && [ "$(cat .agents/last-green)" = "$fp" ]; then
+  if [ -f .agents/run/last-green ] && [ "$(cat .agents/run/last-green)" = "$fp" ]; then
     return 0
   fi
-  if [ -f .agents/last-seen ] && [ "$(cat .agents/last-seen)" = "$fp" ]; then
+  if [ -f .agents/run/last-seen ] && [ "$(cat .agents/run/last-seen)" = "$fp" ]; then
     # Nothing changed since a failing run that was already reported.
     [ "$active" = 1 ] && loop_guard_message
     return 0
   fi
-  if [ ! -f .agents/last-seen ] && [ -z "$(git status --porcelain --untracked-files=all 2>/dev/null | grep -vE ' \.agents/(last-green|last-seen|last-fail|last-run[^/]*\.log|\.gate-lock/)')" ]; then
+  if [ ! -f .agents/run/last-seen ] && [ -z "$(git status --porcelain --untracked-files=all 2>/dev/null | grep -vE ' \.agents/(run/|last-green|last-seen|last-fail|last-run[^/]*\.log|\.gate-lock/)')" ]; then
     # First look, nothing uncommitted: nothing this session changed. Remember the tree and stay quiet.
-    printf '%s\n' "$fp" > .agents/last-seen
+    printf '%s\n' "$fp" > .agents/run/last-seen
     return 0
   fi
 
-  lock=".agents/.gate-lock"
+  lock=".agents/run/.gate-lock"
   if [ -d "$lock" ] && [ -n "$(find "$lock" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
     rmdir "$lock" 2>/dev/null
   fi
@@ -82,11 +82,11 @@ _claude_stop_main() {
   trap "rmdir '$lock' 2>/dev/null" EXIT
 
   out="$(bash scripts/gate.sh fast 2>&1)"; rc=$?
-  printf '%s\n' "$fp" > .agents/last-seen
+  printf '%s\n' "$fp" > .agents/run/last-seen
   case "$rc" in
     0)
-      printf '%s\n' "$fp" > .agents/last-green
-      rm -f .agents/last-fail
+      printf '%s\n' "$fp" > .agents/run/last-green
+      rm -f .agents/run/last-fail
       return 0 ;;
     1) ;;
     *)
@@ -97,8 +97,8 @@ _claude_stop_main() {
   report="$(printf '%s\n' "$out" | head -40)"
   norm="$(printf '%s\n' "$report" | normalise_report)"
   last=""
-  [ -f .agents/last-fail ] && last="$(cat .agents/last-fail)"
-  printf '%s\n' "$norm" > .agents/last-fail
+  [ -f .agents/run/last-fail ] && last="$(cat .agents/run/last-fail)"
+  printf '%s\n' "$norm" > .agents/run/last-fail
   if [ "$active" = 1 ] && [ "$norm" = "$last" ]; then
     loop_guard_message
     return 0
diff --git a/plugins/keel-harness/assets/core/README.agents.md b/plugins/keel-harness/assets/core/README.agents.md
index 7cf4707..3080588 100644
--- a/plugins/keel-harness/assets/core/README.agents.md
+++ b/plugins/keel-harness/assets/core/README.agents.md
@@ -11,12 +11,13 @@ one `warn` line per broken condition, or `harness is clean`.
 | `AGENTS.md`, `<dir>/AGENTS.md` | Instructions every agent reads: commands, "Before you finish", one line per rule. At most 100 lines each | Yes |
 | `CLAUDE.md` | Contains `@AGENTS.md` so Claude Code loads the same instructions | Keep the import |
 | `docs/architecture.md`, `docs/conventions.md`, `docs/testing.md` | Rule prose, one anchored section per rule (`<a id="rule-id"></a>`). At most 300 lines each | Yes |
-| `docs/decisions/NNNN-*.md` | ADRs: why a rule is the way it is. Never edit an accepted one; supersede it | Add new ones |
+| `<adr_dir>/NNNN-*.md` (`adr_dir` in `.agents/state.yml`, default `docs/adr/`) | ADRs: why a rule is the way it is. Never edit an accepted one; supersede it | Add new ones |
 | `.agents/rules/<rule-id>.env` | A rule's metadata and parameters (`LIMIT`, `INCLUDE`, ...), read by its sensor | Yes |
 | `.agents/baselines/<id>.tsv` | Violations that existed when a rule was adopted, per file | Only shrink |
 | `.agents/baselines/archunit/`, `depcruise-known-violations.json` | Native architecture baselines (ArchUnit freeze store, dependency-cruiser known violations); import-linter's is `IGNORE_IMPORTS` in `architecture.env` | Only shrink |
 | `.agents/gate.env` | `CEILING_SECONDS` and `SLOW_CEILING_SECONDS` | Yes |
-| `.agents/state.yml` | Metadata only (`schema_version`, `mode`, `harness_review_by`) | Rarely |
+| `.agents/state.yml` | Metadata only (`schema_version`, `mode`, `harness_review_by`, `adr_dir`) | Rarely |
+| `.agents/run/` | Run state (logs, fingerprints, lock), git-ignored | Never: delete it to reset |
 | `.agents/plans/` | Local migration plans (gitignored) | Yes |
 | `scripts/gate.sh` | Runs `make gate-fast` / `make gate-slow` | No (managed) |
 | `scripts/lib/` | Helpers sourced by sensors (`baseline.sh`, `junit.sh`) | No (managed) |
@@ -37,7 +38,7 @@ Installed scripts start with a "Managed by keel-harness" line. Edit only between
 1. Edit the value in `.agents/rules/<rule-id>.env` (for example `LIMIT=400`).
 2. Edit the same number in the rule's section in its topic file.
 3. Run `make harness-check`; it flags a number that differs between the two.
-4. Write an ADR in `docs/decisions/` if the change is a real trade-off. Loosening the limit (raising a
+4. Write an ADR in the ADR folder (`adr_dir`) if the change is a real trade-off. Loosening the limit (raising a
    `LIMIT`/`MAX`, lowering a `MIN`) always needs one: `guard` fails until an ADR added in the same
    change names `.agents/rules/<rule-id>.env`.
 
@@ -74,7 +75,7 @@ re-running `depcruise-baseline`; for import-linter, delete the fixed edge from `
 4. Run `make harness-check`.
 
 ### Record a decision
-Copy an existing ADR in `docs/decisions/` (MADR: context, decision drivers, considered options,
+Copy an existing ADR in the ADR folder (`adr_dir`; MADR: context, decision drivers, considered options,
 outcome, consequences, evidence), number it `NNNN`, and link it from the rule's **Decision.** line
 and `DECISION=` key. To change a decision, write a new ADR that supersedes the old one.
 
diff --git a/plugins/keel-harness/assets/core/gate.sh b/plugins/keel-harness/assets/core/gate.sh
index 3fc650b..aa5870d 100755
--- a/plugins/keel-harness/assets/core/gate.sh
+++ b/plugins/keel-harness/assets/core/gate.sh
@@ -8,11 +8,11 @@ set -uo pipefail
 mode="${1:-fast}"
 case "$mode" in fast | slow) ;; *) echo "usage: gate.sh [fast|slow]" >&2; exit 64 ;; esac
 cd "$(dirname "$0")/.." || exit 1
-mkdir -p .agents
+mkdir -p .agents/run
 if [ "$mode" = slow ]; then
-  dir="scripts/sensors/slow"; log=".agents/last-run-slow.log"; key=SLOW_CEILING_SECONDS; default=600
+  dir="scripts/sensors/slow"; log=".agents/run/last-run-slow.log"; key=SLOW_CEILING_SECONDS; default=600
 else
-  dir="scripts/sensors"; log=".agents/last-run.log"; key=CEILING_SECONDS; default=30
+  dir="scripts/sensors"; log=".agents/run/last-run.log"; key=CEILING_SECONDS; default=30
 fi
 
 # Millisecond clock, portable: `date +%s%N` is GNU-only. Bash 5+ has $EPOCHREALTIME (its decimal
@@ -42,12 +42,13 @@ fi
 : "${ceiling:=$default}"
 
 # SCOPE = files changed since the last commit (tracked, not deleted, plus untracked), minus
-# keel's own run state (.agents/last-*, .agents/.gate-lock/) in case .gitignore misses it.
+# keel's own run state (.agents/run/, and v0.2's .agents/last-* and .agents/.gate-lock/) in case
+# .gitignore misses it.
 # Empty means the whole repository, which is also the case before the first commit.
 if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
   SCOPE="$({ git -c core.quotepath=off diff --name-only --diff-filter=d HEAD 2>/dev/null
     git -c core.quotepath=off ls-files --others --exclude-standard 2>/dev/null; } | sed '/^$/d' |
-    grep -vE '^\.agents/(last-[^/]*|\.gate-lock/.*)$' | sort -u)"
+    grep -vE '^\.agents/(run/.*|last-[^/]*|\.gate-lock/.*)$' | sort -u)"
   empty_scope_note="no uncommitted changes"
 else
   SCOPE=""
diff --git a/plugins/keel-harness/assets/core/harness-check.sh b/plugins/keel-harness/assets/core/harness-check.sh
index 1969b18..57f3fe6 100755
--- a/plugins/keel-harness/assets/core/harness-check.sh
+++ b/plugins/keel-harness/assets/core/harness-check.sh
@@ -128,6 +128,19 @@ check_hook_missing() {
   warn hook-missing .claude/settings.json "no Stop hook pointing at an executable scripts/hooks/claude-stop.sh" "Run /keel-harness:build to install the Stop hook, or see .agents/README.md"
 }
 
+# --- run-state
+check_run_state() {
+  local f legacy=""
+  for f in .agents/last-run.log .agents/last-run-slow.log .agents/last-green .agents/last-seen .agents/last-fail .agents/.gate-lock; do
+    [ -e "$f" ] && legacy="$legacy $f"
+  done
+  [ -n "$legacy" ] && warn run-state .agents "run state from an earlier keel outside .agents/run/:$legacy" "Run /keel-harness:build to upgrade, or delete those files; keel now keeps run state in .agents/run/"
+  if ! git check-ignore -q .agents/run/last-run.log 2>/dev/null || [ -n "$(git ls-files .agents/run 2>/dev/null)" ]; then
+    warn run-state .gitignore ".agents/run/ is not ignored, so run state can be committed" "Add .agents/run/ to .gitignore (and git rm -r --cached .agents/run if it is tracked)"
+  fi
+  return 0
+}
+
 # --- guard-missing
 check_guard_missing() {
   [ -f scripts/sensors/guard.sh ] && [ -f scripts/lib/envparse.sh ] && return 0
@@ -284,6 +297,7 @@ check_stale_command
 check_agents_not_loaded
 check_dangling_pointer
 check_hook_missing
+check_run_state
 check_guard_missing
 check_sensor_malformed
 check_sensor_unavailable
diff --git a/plugins/keel-harness/assets/core/sensors/common/guard.sh b/plugins/keel-harness/assets/core/sensors/common/guard.sh
index e48a286..ed8289f 100755
--- a/plugins/keel-harness/assets/core/sensors/common/guard.sh
+++ b/plugins/keel-harness/assets/core/sensors/common/guard.sh
@@ -39,6 +39,10 @@ if ! git cat-file -e "$base:.agents/state.yml" 2>/dev/null; then
   exit 0
 fi
 
+# The ADR folder the rules skill recorded wins over the default list.
+adr_dir="$(sed -n 's/^adr_dir:[[:space:]]*\([^#[:space:]]*\).*/\1/p' .agents/state.yml 2>/dev/null | head -1)"
+[ -n "$adr_dir" ] && ADR_DIRS="$adr_dir"
+
 tmp="$(mktemp -d)"
 trap 'rm -rf "$tmp"' EXIT
 : > "$tmp/loose"
diff --git a/plugins/keel-harness/assets/core/sensors/jvm/tests.sh b/plugins/keel-harness/assets/core/sensors/jvm/tests.sh
index ecf49b4..7f6c5c1 100755
--- a/plugins/keel-harness/assets/core/sensors/jvm/tests.sh
+++ b/plugins/keel-harness/assets/core/sensors/jvm/tests.sh
@@ -13,7 +13,7 @@ class=correctness
 BUILD="gradle"
 CMD=(./gradlew -q)
 # Maven: BUILD="maven" CMD=(./mvnw -q -o)
-GUIDANCE='a test that passed before now fails, so behaviour changed. Read the failing assertion above (expected vs actual), then look at what changed in the source class it exercises - git diff shows it. If that behaviour change was NOT intended, revert it in the source; do not edit the test to match the new value. If it WAS intended, update the test and record the decision in docs/decisions/ as a new ADR - never edit an accepted one.'
+GUIDANCE='a test that passed before now fails, so behaviour changed. Read the failing assertion above (expected vs actual), then look at what changed in the source class it exercises - git diff shows it. If that behaviour change was NOT intended, revert it in the source; do not edit the test to match the new value. If it WAS intended, update the test and record the decision as a new ADR in the folder adr_dir names in .agents/state.yml (docs/adr/ by default) - never edit an accepted one.'
 # --- keel:repo-specific end ---
 
 case "${CMD[0]}" in
diff --git a/plugins/keel-harness/assets/core/sensors/python/tests.sh b/plugins/keel-harness/assets/core/sensors/python/tests.sh
index acaa4d5..4e1fa5e 100755
--- a/plugins/keel-harness/assets/core/sensors/python/tests.sh
+++ b/plugins/keel-harness/assets/core/sensors/python/tests.sh
@@ -12,7 +12,7 @@ class=correctness
 # --- keel:repo-specific begin ---
 CMD=(.venv/bin/pytest -q)
 TEST_ROOT="tests"
-GUIDANCE='a test that passed before now fails, so behaviour changed. Read the failing assertion above (expected vs received), then look at what changed in the source file it exercises - git diff shows it. If that behaviour change was NOT intended, revert it in the source; do not edit the test to match the new value. If it WAS intended, update the test and record the decision in docs/decisions/ as a new ADR - never edit an accepted one.'
+GUIDANCE='a test that passed before now fails, so behaviour changed. Read the failing assertion above (expected vs received), then look at what changed in the source file it exercises - git diff shows it. If that behaviour change was NOT intended, revert it in the source; do not edit the test to match the new value. If it WAS intended, update the test and record the decision as a new ADR in the folder adr_dir names in .agents/state.yml (docs/adr/ by default) - never edit an accepted one.'
 # --- keel:repo-specific end ---
 
 case "${CMD[0]}" in
diff --git a/plugins/keel-harness/assets/core/sensors/typescript/tests.sh b/plugins/keel-harness/assets/core/sensors/typescript/tests.sh
index f0d6b1b..5467d58 100755
--- a/plugins/keel-harness/assets/core/sensors/typescript/tests.sh
+++ b/plugins/keel-harness/assets/core/sensors/typescript/tests.sh
@@ -10,7 +10,7 @@ class=correctness
 # --- keel:repo-specific begin ---
 RUNNER="vitest"
 BIN="node_modules/.bin/vitest"
-GUIDANCE='a test that passed before now fails, so behaviour changed. Read the failing assertion above (expected vs received), then look at what changed in the source file it exercises - git diff shows it. If that behaviour change was NOT intended, revert it in the source; do not edit the test to match the new number. If it WAS intended, update the test and record the decision in docs/decisions/ as a new ADR - never edit an accepted one.'
+GUIDANCE='a test that passed before now fails, so behaviour changed. Read the failing assertion above (expected vs received), then look at what changed in the source file it exercises - git diff shows it. If that behaviour change was NOT intended, revert it in the source; do not edit the test to match the new number. If it WAS intended, update the test and record the decision as a new ADR in the folder adr_dir names in .agents/state.yml (docs/adr/ by default) - never edit an accepted one.'
 # --- keel:repo-specific end ---
 
 if [ ! -x "$BIN" ]; then
diff --git a/plugins/keel-harness/evals/build-java/graders/state-yml.md b/plugins/keel-harness/evals/build-java/graders/state-yml.md
index 8de3e48..7da8c6d 100644
--- a/plugins/keel-harness/evals/build-java/graders/state-yml.md
+++ b/plugins/keel-harness/evals/build-java/graders/state-yml.md
@@ -1,6 +1,6 @@
 ---
 type: regex
-pattern: 'schema_version: 2[\s\S]*layers:[\s\S]*(bootstrap|guides)'
+pattern: 'schema_version: 3[\s\S]*layers:[\s\S]*(bootstrap|guides)'
 target: { source: file, path: .agents/state.yml }
 weight: 2
 ---
diff --git a/plugins/keel-harness/evals/build-python/graders/state-yml.md b/plugins/keel-harness/evals/build-python/graders/state-yml.md
index 8de3e48..7da8c6d 100644
--- a/plugins/keel-harness/evals/build-python/graders/state-yml.md
+++ b/plugins/keel-harness/evals/build-python/graders/state-yml.md
@@ -1,6 +1,6 @@
 ---
 type: regex
-pattern: 'schema_version: 2[\s\S]*layers:[\s\S]*(bootstrap|guides)'
+pattern: 'schema_version: 3[\s\S]*layers:[\s\S]*(bootstrap|guides)'
 target: { source: file, path: .agents/state.yml }
 weight: 2
 ---
diff --git a/plugins/keel-harness/evals/build-react/graders/state-yml.md b/plugins/keel-harness/evals/build-react/graders/state-yml.md
index 8de3e48..7da8c6d 100644
--- a/plugins/keel-harness/evals/build-react/graders/state-yml.md
+++ b/plugins/keel-harness/evals/build-react/graders/state-yml.md
@@ -1,6 +1,6 @@
 ---
 type: regex
-pattern: 'schema_version: 2[\s\S]*layers:[\s\S]*(bootstrap|guides)'
+pattern: 'schema_version: 3[\s\S]*layers:[\s\S]*(bootstrap|guides)'
 target: { source: file, path: .agents/state.yml }
 weight: 2
 ---
diff --git a/plugins/keel-harness/evals/build-typescript/graders/state-yml.md b/plugins/keel-harness/evals/build-typescript/graders/state-yml.md
index 8de3e48..7da8c6d 100644
--- a/plugins/keel-harness/evals/build-typescript/graders/state-yml.md
+++ b/plugins/keel-harness/evals/build-typescript/graders/state-yml.md
@@ -1,6 +1,6 @@
 ---
 type: regex
-pattern: 'schema_version: 2[\s\S]*layers:[\s\S]*(bootstrap|guides)'
+pattern: 'schema_version: 3[\s\S]*layers:[\s\S]*(bootstrap|guides)'
 target: { source: file, path: .agents/state.yml }
 weight: 2
 ---
diff --git a/plugins/keel-harness/evals/build-typescript/scaffold.sh b/plugins/keel-harness/evals/build-typescript/scaffold.sh
index 3a7058c..4ad4c36 100755
--- a/plugins/keel-harness/evals/build-typescript/scaffold.sh
+++ b/plugins/keel-harness/evals/build-typescript/scaffold.sh
@@ -55,7 +55,7 @@ export const config = { stripeKey: STRIPE_KEY };
 TS
 cat > .gitignore <<'GITIGNORE'
 node_modules/
-.agents/last-run.log
+.agents/run/
 GITIGNORE
 
 npm install --no-audit --no-fund --silent
diff --git a/plugins/keel-harness/evals/gate-catches-defect/fixtures/harness/.agents/state.yml b/plugins/keel-harness/evals/gate-catches-defect/fixtures/harness/.agents/state.yml
index d1f627e..be7a2b9 100644
--- a/plugins/keel-harness/evals/gate-catches-defect/fixtures/harness/.agents/state.yml
+++ b/plugins/keel-harness/evals/gate-catches-defect/fixtures/harness/.agents/state.yml
@@ -1,4 +1,4 @@
-schema_version: 2
+schema_version: 3
 installed_at: 2026-10-20
 harness_review_by: 2027-04-20
 mode: brownfield
diff --git a/plugins/keel-harness/evals/rules-brownfield/graders/context-adr.md b/plugins/keel-harness/evals/rules-brownfield/graders/context-adr.md
index 865de5b..1a33f07 100644
--- a/plugins/keel-harness/evals/rules-brownfield/graders/context-adr.md
+++ b/plugins/keel-harness/evals/rules-brownfield/graders/context-adr.md
@@ -1,4 +1,4 @@
 ---
 type: file_exists
-path: docs/decisions/0001-agent-harness-context.md
+path: docs/adr/0001-agent-harness-context.md
 ---
diff --git a/plugins/keel-harness/evals/rules-brownfield/harness.sh b/plugins/keel-harness/evals/rules-brownfield/harness.sh
index d43abbc..0de59e6 100644
--- a/plugins/keel-harness/evals/rules-brownfield/harness.sh
+++ b/plugins/keel-harness/evals/rules-brownfield/harness.sh
@@ -56,7 +56,7 @@ Run `make gate-fast` and read it before you say you are done:
 Before opening a pull request, also run `make gate-slow`.
 MD
   printf '@AGENTS.md\n' > CLAUDE.md
-  printf '.agents/last-run.log\n.agents/last-run-slow.log\n.agents/last-green\n.agents/last-seen\n.agents/last-fail\n.agents/.gate-lock/\n' >> .gitignore
+  printf '.agents/run/\n' >> .gitignore
 }
 
 # install_rule_sensors <id>...  copies rule sensors from the rules skill (slow ones into slow/)
diff --git a/plugins/keel-harness/skills/assess/SKILL.md b/plugins/keel-harness/skills/assess/SKILL.md
index b176164..e272763 100644
--- a/plugins/keel-harness/skills/assess/SKILL.md
+++ b/plugins/keel-harness/skills/assess/SKILL.md
@@ -66,7 +66,7 @@ grep -l '@AGENTS.md' CLAUDE.md .claude/CLAUDE.md 2>/dev/null
 
 # Architecture tool configs, mutation tooling, rules and decisions
 ls .dependency-cruiser.cjs .dependency-cruiser.js .importlinter stryker.conf.* mutmut_config.py \
-   docs/architecture.md docs/conventions.md docs/testing.md docs/decisions .husky lefthook.yml 2>/dev/null
+   docs/architecture.md docs/conventions.md docs/testing.md docs/adr doc/adr docs/decisions .husky lefthook.yml 2>/dev/null
 grep -lE 'archunit|pitest|info.solidsoft.pitest' pom.xml build.gradle build.gradle.kts 2>/dev/null
 ```
 
diff --git a/plugins/keel-harness/skills/build/SKILL.md b/plugins/keel-harness/skills/build/SKILL.md
index 99529b9..79c7693 100644
--- a/plugins/keel-harness/skills/build/SKILL.md
+++ b/plugins/keel-harness/skills/build/SKILL.md
@@ -168,23 +168,24 @@ continues only while the gate fails, up to its loop guard.
 Claude Code sets when it runs the hook; never replace it with this repository's absolute path. The
 hook is the item most worth declining on its own, so it is a separate line in the proposal.
 
-Add these to `.gitignore` (fresh installs and upgrades alike): `.agents/last-run.log`,
-`.agents/last-run-slow.log`, `.agents/last-green`, `.agents/last-seen`, `.agents/last-fail`, `.agents/.gate-lock/`,
-`.agents/plans/`. Propose ignoring the tools' caches too when they are not (`.mypy_cache/`,
+Add `.agents/run/` (all run state: logs, fingerprints, lock) and `.agents/plans/` to `.gitignore`,
+fresh installs and upgrades alike. Propose ignoring the tools' caches too when they are not (`.mypy_cache/`,
 `.pytest_cache/`, `.ruff_cache/`, `.gradle/`, `build/`, `coverage/`): untracked, they enter `SCOPE`.
 
-## 7b. Upgrading a v0.1 install
+## 7b. Upgrading an earlier install
 
-A repository whose `.agents/state.yml` lacks `schema_version: 2`, or whose `.claude/settings.json`
-has a `PostToolUse` entry running `make gate-fast`, gets one round that proposes, each item
-accept-or-drop:
+A `schema_version: 2` state (v0.2) gets one round, each item accept-or-drop: delete `.agents/last-*` and
+`.agents/.gate-lock/`, replace their seven `.gitignore` lines with `.agents/run/`, install `scripts/lib/envparse.sh`,
+`scripts/sensors/guard.sh` and current copies of every asset (outside the repo-specific markers), set
+`schema_version: 3`; then `make harness-check` reports no `run-state` or `guard-missing`. A state without
+`schema_version`, or a `PostToolUse` entry running `make gate-fast` (v0.1), gets that round plus:
 
 1. The Stop hook of section 7 replaces the v0.1 PostToolUse entry (remove that entry, keep other keys).
 2. The sensor list in the old state is dropped: each entry already has its file; the gate
    discovers files now.
 3. A v0.1 `snapshot` entry becomes a TSV baseline, re-measured with `KEEL_MEASURE=1`, never copied, and named in one upgrade ADR so `guard` accepts it.
 4. The v0.1 model-baseline key is replaced by `harness_review_by` (today + 6 months); state becomes section 9.
-5. The `.gitignore` entries above are added.
+5. The `.gitignore` entries of section 7 are added.
 
 ## 8. Propose, then write
 
@@ -212,7 +213,7 @@ State is **metadata only**; it does not configure the gate (budgets are in `.age
 sensors are the files in `scripts/sensors/`).
 
 ```yaml
-schema_version: 2
+schema_version: 3
 installed_at: 2026-10-20          # ISO date, today
 harness_review_by: 2027-04-20     # installed_at + 6 months
 mode: brownfield                  # greenfield | brownfield, confirmed by the user
@@ -230,7 +231,7 @@ Check what the copied assets do not already guarantee:
 - [ ] `AGENTS.md` is 100 lines or fewer; deep content is `→ docs/X.md` pointers; no `{{...}}` left.
 - [ ] Every command cited in `AGENTS.md` really exists and runs here (re-check by hand).
 - [ ] `Last updated: YYYY-MM-DD` is set; nothing was written before the user confirmed.
-- [ ] `.agents/state.yml` parses as YAML and has `schema_version: 2`.
+- [ ] `.agents/state.yml` parses as YAML and has `schema_version: 3`; `.gitignore` ignores `.agents/run/`.
 - [ ] `make gate-fast` was actually run and its output read; its verdict line reads
       `gate: fast - ...` and each sensor's `cut -f1` is its own id.
 - [ ] `make harness-check` was run and prints `harness is clean`.
diff --git a/plugins/keel-harness/skills/build/references/agents-md-template.md b/plugins/keel-harness/skills/build/references/agents-md-template.md
index 7e2538e..e18c0bd 100644
--- a/plugins/keel-harness/skills/build/references/agents-md-template.md
+++ b/plugins/keel-harness/skills/build/references/agents-md-template.md
@@ -14,7 +14,7 @@ Sections, in this order. Each is omitted when empty:
 2. `## Commands`: purpose, command, pass signal;
 3. `## Before you finish`: the exact copy below, unchanged;
 4. `## Rules`: one line per rule, each pointing at `docs/<topic>.md#<id>` (filled by the `rules` skill);
-5. `## Decisions`: a pointer to `docs/decisions/` when ADRs exist;
+5. `## Decisions`: a pointer to the ADR folder (`adr_dir` in `.agents/state.yml`) when ADRs exist;
 6. `## Reading tool output`: at most 4 bullets.
 
 ---
@@ -42,7 +42,7 @@ Before opening a pull request, also run `make gate-slow`.
 - {{rule statement, one verifiable sentence}} → docs/{{topic}}.md#{{id}}
 
 ## Decisions
-Why things are the way they are → docs/decisions/
+Why things are the way they are → {{adr_dir}}/
 
 ## Reading tool output
 - The first error in a chain is the root cause; the rest cascade. Fix top-down.
diff --git a/plugins/keel-harness/skills/build/references/sensor-contract.md b/plugins/keel-harness/skills/build/references/sensor-contract.md
index 16e5c11..f8c44ed 100644
--- a/plugins/keel-harness/skills/build/references/sensor-contract.md
+++ b/plugins/keel-harness/skills/build/references/sensor-contract.md
@@ -22,7 +22,7 @@ regenerate a wrapper from this document; this document explains the contract tho
 | 2 | **guidance** | On failure, what to do next **in the repository's own terms** - which file, which decision, what action. Never a restatement of the tool's error. | the `guidance: ` block on `fail` |
 | 3 | **scope** | What the sensor looked at: the changed files (`SCOPE`) or the whole repository. A sensor whose tool has no file-level mode says so. | `SCOPE` in, the summary out |
 | 4 | **cost** | Wall time in milliseconds, measured by `gate.sh` from outside. The money cost of the gates is **US$0.00**: no sensor calls a language model. | `gate.sh` report |
-| 5 | **bounded verbosity** | At most 5 detail lines per sensor, indented two spaces; `gate.sh` truncates its stdout at 40 lines and keeps the full run in `.agents/last-run.log` (`last-run-slow.log` for the slow gate). | the sensor, then `gate.sh` |
+| 5 | **bounded verbosity** | At most 5 detail lines per sensor, indented two spaces; `gate.sh` truncates its stdout at 40 lines and keeps the full run in `.agents/run/last-run.log` (`.agents/run/last-run-slow.log` for the slow gate). | the sensor, then `gate.sh` |
 | 6 | **class** | `security`, `correctness` or `heuristic` (section 2). | line 1 |
 | 7 | **ceiling** | `CEILING_SECONDS` (default 30) and `SLOW_CEILING_SECONDS` (default 600) in `.agents/gate.env`. The total over the budget is flagged `(over ceiling)`; a sensor that alone blows the fast budget is left out or moved to the slow gate, and `.agents/state.yml` says which and why. | `.agents/gate.env` |
 
diff --git a/plugins/keel-harness/skills/doctor/SKILL.md b/plugins/keel-harness/skills/doctor/SKILL.md
index 3655dc1..4181a09 100644
--- a/plugins/keel-harness/skills/doctor/SKILL.md
+++ b/plugins/keel-harness/skills/doctor/SKILL.md
@@ -4,7 +4,7 @@ description: >
   Checks whether an installed harness has drifted from the repository it guards, by running the
   same portable validator the repository carries: AGENTS.md over 100 lines, commands cited there
   that no longer resolve, a CLAUDE.md that hides AGENTS.md, dangling rule pointers, a missing Stop
-  hook, a missing guard sensor, malformed or unavailable sensors, rules that disagree with their env files, oversize topic
+  hook, misplaced or unignored run state, a missing guard sensor, malformed or unavailable sensors, rules that disagree with their env files, oversize topic
   files, malformed or stale baselines, and an overdue harness review. Explains each warning and
   proposes the fix; writes nothing. Use when someone asks whether their harness is out of date,
   stale or still valid, or wants a harness health check.
@@ -29,7 +29,7 @@ then `harness-check: N warning(s)` or `harness-check: harness is clean`. Exit 0
 2 no harness: with no `.agents/state.yml`, say so and point at `/keel-harness:build`; that is a
 precondition, not a warning.
 
-## 2. The thirteen checks
+## 2. The fourteen checks
 
 | Check id | Condition | Fix goes through |
 | --- | --- | --- |
@@ -38,6 +38,7 @@ precondition, not a warning.
 | `agents-not-loaded` | `CLAUDE.md` or `.claude/CLAUDE.md` exists without `@AGENTS.md` | `build` (it proposes the import line) |
 | `dangling-pointer` | a `→ path#anchor` target, file or anchor, is missing or still a TODO stub | `rules` |
 | `hook-missing` | no Stop hook pointing at an executable `scripts/hooks/claude-stop.sh` | `build` (hook) |
+| `run-state` | v0.2 run state outside `.agents/run/`, or `.agents/run/` not ignored | `build` (upgrade, section 7b) |
 | `guard-missing` | no `scripts/sensors/guard.sh` or no `scripts/lib/envparse.sh` | `build` (gates) |
 | `sensor-malformed` | a sensor whose `id=` differs from its file name, whose `class=` is invalid, or that is not executable | edit the file, or `build` |
 | `sensor-unavailable` | a fast sensor exits 2 for a tracked file it covers (tool missing) | `build` (gates) |
diff --git a/plugins/keel-harness/skills/rules/SKILL.md b/plugins/keel-harness/skills/rules/SKILL.md
index ea90e39..9632bee 100644
--- a/plugins/keel-harness/skills/rules/SKILL.md
+++ b/plugins/keel-harness/skills/rules/SKILL.md
@@ -32,9 +32,11 @@ run yet; a gate with zero sensors is valid). Continue only when the user agrees
 
 ## 1. Context interview
 
-One round before any measurement, in at most 4 questions, from `references/interview.md`. Record the
-answers in `docs/decisions/0001-agent-harness-context.md` (the first ADR, `adr-template.md`) and let
-them steer every proposal.
+One round before any measurement, in at most 4 questions, from `references/interview.md`. First pick
+the **ADR folder**: an existing one (`docs/adr/`, `doc/adr/`, `docs/decisions/`, `docs/architecture/decisions/`,
+in that order), else `docs/adr/`. Record it as `adr_dir: <folder>` in `.agents/state.yml`; every ADR path
+below is in that folder. Record the answers in `<adr_dir>/0001-agent-harness-context.md` (the first ADR,
+`adr-template.md`) and let them steer every proposal.
 
 ## 2. Mode
 
@@ -84,7 +86,7 @@ option of each question and say so. Group by topic: architecture, then testing,
 
 Write only what was approved, in this order:
 
-1. The ADR in `docs/decisions/`, when the round had a real trade-off, the rule is breaking, or the
+1. The ADR in `<adr_dir>/`, when the round had a real trade-off, the rule is breaking, or the
    user overrode your recommendation (`adr-template.md`). Never edit an accepted ADR: supersede it.
    The ADR names, by path, every baseline it introduces and every env file it loosens: `guard` accepts
    a new or grown baseline, or a relaxed limit, only when an ADR added in the same change names it.
diff --git a/plugins/keel-harness/skills/rules/references/adr-template.md b/plugins/keel-harness/skills/rules/references/adr-template.md
index f7d2630..dfc90cf 100644
--- a/plugins/keel-harness/skills/rules/references/adr-template.md
+++ b/plugins/keel-harness/skills/rules/references/adr-template.md
@@ -1,6 +1,6 @@
 # ADR template (MADR)
 
-ADRs live in `docs/decisions/NNNN-<slug>.md`, numbered `NNNN` from `0001`. Write one when a round had
+ADRs live in `<adr_dir>/NNNN-<slug>.md` (`adr_dir` in `.agents/state.yml`, default `docs/adr/`), numbered `NNNN` from `0001`. Write one when a round had
 a real trade-off (more than one viable option), when a rule is breaking, or when the user overrides
 your recommendation. **Never edit an accepted ADR; supersede it** with a new one that links back,
 and set the old one's status to `superseded by NNNN`.
diff --git a/plugins/keel-harness/skills/rules/references/interview.md b/plugins/keel-harness/skills/rules/references/interview.md
index 409aadf..1e39db4 100644
--- a/plugins/keel-harness/skills/rules/references/interview.md
+++ b/plugins/keel-harness/skills/rules/references/interview.md
@@ -5,7 +5,7 @@ available: recommended option first, each option with its trade-off, plus a free
 non-interactive run, ask in plain text; when the user's request pre-authorised proceeding, take the
 recommended option of each question and say so.
 
-The answers are recorded in `docs/decisions/0001-agent-harness-context.md` (the first ADR, from
+The answers are recorded in `<adr_dir>/0001-agent-harness-context.md` (the first ADR, from
 `adr-template.md`) and steer every later proposal. Do not interrogate: if the repository already
 answers a question, state what you found and ask only for confirmation.
 
diff --git a/plugins/keel-harness/skills/rules/references/plan-template.md b/plugins/keel-harness/skills/rules/references/plan-template.md
index a6a1db7..8539e52 100644
--- a/plugins/keel-harness/skills/rules/references/plan-template.md
+++ b/plugins/keel-harness/skills/rules/references/plan-template.md
@@ -7,7 +7,7 @@ file. keel never executes it; any agent or person can pick it up later.
 ```markdown
 # Migration plan: {{rule-id}}
 Written: {{YYYY-MM-DD}} · review_by: {{YYYY-MM-DD, six months out}}
-Rule: {{docs/<topic>.md#<rule-id>}} · Decision: {{docs/decisions/NNNN-slug.md}}
+Rule: {{docs/<topic>.md#<rule-id>}} · Decision: {{<adr_dir>/NNNN-slug.md}}
 Goal: {{baseline today, e.g. "file-size baseline: 12 files"}} -> {{target, e.g. 0 files}}
 
 ## Steps
diff --git a/plugins/keel-harness/skills/rules/references/rule-env.md b/plugins/keel-harness/skills/rules/references/rule-env.md
index 2b2279b..cde294d 100644
--- a/plugins/keel-harness/skills/rules/references/rule-env.md
+++ b/plugins/keel-harness/skills/rules/references/rule-env.md
@@ -14,7 +14,7 @@ ORIGIN=proposed                   # discovered | proposed | user
 APPROVED_AT=2026-10-20
 ENFORCEMENT=sensor:file-size      # sensor:<id>[,sensor:<id>] | inferential
 DOC=docs/conventions.md#file-size
-DECISION=docs/decisions/0003-file-size-limit.md   # optional
+DECISION=docs/adr/0003-file-size-limit.md         # optional; in adr_dir
 PLAN=.agents/plans/2026-10-20-file-size.md        # optional; local, may be absent on other clones
 LIMIT=300
 INCLUDE='src/'
```

- [ ] **Step 2: verify.**
  - `./tests/run.sh; echo rc=$?` → `rc=0`, **1028** `ok` (1031 if E1 is in).
  - `wc -l < plugins/keel-harness/skills/build/SKILL.md` → `249`.
  - `claude plugin validate ./plugins/keel-harness --strict` → `Validation passed`.
  - `grep -rn 'docs/decisions' plugins/keel-harness | grep -v 'guard.sh\|rules/SKILL.md\|assess/SKILL.md'` → no output. `docs/decisions` is now only one of the detected folders.
- [ ] **Step 3: end to end** in a scratch directory (expected output in the comments):

```bash
K=<repo>/plugins/keel-harness; d=$(mktemp -d); cd "$d" && git init -q && git config user.email t@t && git config user.name t
mkdir -p scripts/sensors scripts/lib scripts/hooks .agents/rules .agents/baselines .claude src docs
cp $K/assets/core/gate.sh $K/assets/core/harness-check.sh scripts/; cp $K/assets/core/lib/*.sh scripts/lib/
cp $K/assets/core/sensors/common/guard.sh $K/assets/core/sensors/rules/file-size.sh scripts/sensors/
cp $K/assets/adapters/claude/claude-stop.sh scripts/hooks/; cp $K/assets/adapters/claude/settings-stop.json .claude/settings.json
cp $K/assets/core/gate.env .agents/; chmod +x scripts/*.sh scripts/*/*.sh
printf 'schema_version: 3\nlayers: { hook: installed }\n' > .agents/state.yml
printf 'RULE_ID=file-size\nKIND=metric\nORIGIN=user\nAPPROVED_AT=2026-10-28\nENFORCEMENT=sensor:file-size\nDOC=docs/c.md#file-size\nLIMIT=10\nINCLUDE=src\n' > .agents/rules/file-size.env
printf '<a id="file-size"></a>\nLIMIT 10\n' > docs/c.md; printf '.agents/run/\n' > .gitignore
git add -A && git commit -qm h && seq 1 20 > src/big.txt
bash scripts/gate.sh fast | tail -1                 # full log in .agents/run/last-run.log
echo '{}' | bash scripts/hooks/claude-stop.sh | head -c 60; echo   # {"hookSpecificOutput":{"hookEventName":"Stop",...
ls .agents/run                                      # last-fail  last-run.log  last-seen
git status --porcelain                              # ?? src/   (run state is ignored)
bash scripts/harness-check.sh | tail -1             # harness-check: harness is clean
touch .agents/last-green; bash scripts/harness-check.sh | cut -f2 | grep run-state   # run-state
```

- [ ] **Step 4: commit and push.** `feat(keel-harness): run state in .agents/run/, ADR folder (adr_dir), schema_version 3 (F2b)`

## Task 3 — record and report

- [ ] **Step 1:** tick the F2b items in `docs/plans/2026-10-23-keel-harness-v0.3-plan.md`; commit `docs(keel-harness): F2b done` and push.
- [ ] **Step 2: report to the owner:**
  - the commits;
  - the Task 1 Step 2 list;
  - the Task 2 Step 2 and Step 3 outputs;
  - any deviation from this plan.

  Do not open a pull request.

**Known follow-ups, not F2b:** `.agents/plans/` stays ignored until F3b (D40). The eval graders now expect `schema_version: 3`, so `build-*` scores after F2b are compared with F1b's against the new expectation.
