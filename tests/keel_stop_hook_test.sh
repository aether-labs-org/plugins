#!/usr/bin/env bash
set -uo pipefail
qgrep() { grep "$@" >/dev/null; } # reads all its input: `| grep -q` can SIGPIPE the writer under pipefail
. "$(dirname "$0")/keel_helpers.sh"
HOOK_SRC="$KEEL/assets/adapters/claude/claude-stop.sh"
[ -f "$HOOK_SRC" ]; check "claude-stop.sh exists" $?
# shellcheck disable=SC1090
. "$HOOK_SRC" 2>/dev/null

# --- json_escape
got="$(json_escape "$(printf 'a"b\\c\td\ne\001')")"
[ "$got" = 'a\"b\\c\td\ne\u0001' ]; check "json_escape escapes quote, backslash, tab, newline, control" $?
[ "$(json_escape 'plain ação')" = 'plain ação' ]; check "json_escape leaves UTF-8 alone" $?

# stub gate: STUB_RC and STUB_OUT_FILE are read from the environment (outside the repo)
mkrepo() {
  local r; r="$(new_repo "$@")"
  mkdir -p "$r/scripts/hooks" "$r/.agents"
  cp "$HOOK_SRC" "$r/scripts/hooks/claude-stop.sh"; chmod +x "$r/scripts/hooks/claude-stop.sh"
  cat > "$r/scripts/gate.sh" <<'G'
#!/usr/bin/env bash
echo ran >> "${GATE_RAN:-/dev/null}"
[ -n "${STUB_OUT_FILE:-}" ] && cat "$STUB_OUT_FILE"
exit "${STUB_RC:-0}"
G
  printf '%s\n' "$r"
}
W="$(mktemp -d)"; _keel_tmps="$_keel_tmps $W"
FAILOUT="$W/fail.txt"
printf 'x tests [correctness] Tests 1 failed (1) 2.1s\n  guidance: fix the thing\n\nscope: 1 files changed since last commit\ngate: fast - FAILED (1 of 1) | ceiling 30s, spent 2.1s | model cost: US$0.00\n' > "$FAILOUT"
hook() { # hook REPO [stdin] [env...] -> out, rc
  local r="$1" in="$2"; shift 2
  out="$(cd "$r" && printf '%s' "$in" | env GATE_RAN="$W/ran" "$@" bash scripts/hooks/claude-stop.sh 2>/dev/null)"; rc=$?
}
ran() { [ -f "$W/ran" ] && wc -l < "$W/ran" | tr -d ' ' || echo 0; }

# --- fingerprint
r="$(mkrepo)"; echo a > "$r/t.txt"; (cd "$r" && git add t.txt && git commit -q -m t)
f1="$(cd "$r" && tree_fingerprint)"; f1b="$(cd "$r" && tree_fingerprint)"
[ -n "$f1" ] && [ "$f1" = "$f1b" ]; check "fingerprint stable" $?
echo b >> "$r/t.txt"; f2="$(cd "$r" && tree_fingerprint)"; [ "$f1" != "$f2" ]; check "fingerprint changes after tracked edit" $?
echo u > "$r/u.txt"; f3="$(cd "$r" && tree_fingerprint)"; echo uu > "$r/u.txt"; f4="$(cd "$r" && tree_fingerprint)"
[ "$f2" != "$f3" ] && [ "$f3" != "$f4" ]; check "fingerprint changes after untracked add and edit" $?
r="$(mkrepo --no-commit)"; echo a > "$r/u.txt"; g1="$(cd "$r" && tree_fingerprint)"; echo b > "$r/u.txt"; g2="$(cd "$r" && tree_fingerprint)"
[ -n "$g1" ] && [ "$g1" != "$g2" ]; check "fingerprint works without commits (RF2)" $?

# --- skip when equal to last-green
r="$(mkrepo)"; echo a > "$r/t.txt"; rm -f "$W/ran"
(cd "$r" && mkdir -p .agents/run && tree_fingerprint > .agents/run/last-green)
hook "$r" '{}'; [ -z "$out" ] && [ $rc -eq 0 ] && [ "$(ran)" = 0 ]; check "fingerprint == last-green: silent, gate not run" $?

# --- pass
r="$(mkrepo)"; echo a > "$r/t.txt"; rm -f "$W/ran"
hook "$r" '{}' STUB_RC=0
[ -z "$out" ] && [ $rc -eq 0 ] && [ -s "$r/.agents/run/last-green" ] && [ "$(ran)" = 1 ]; check "pass: silent, last-green written" $?
hook "$r" '{}' STUB_RC=0; [ "$(ran)" = 1 ]; check "second run on same tree skips the gate" $?

# --- fail
r="$(mkrepo)"; echo a > "$r/t.txt"
hook "$r" '{}' STUB_RC=1 STUB_OUT_FILE="$FAILOUT"
[ $rc -eq 0 ]; check "fail: rc 0" $?
printf '%s' "$out" | python3 -c '
import sys, json
d = json.load(sys.stdin)
h = d["hookSpecificOutput"]
assert h["hookEventName"] == "Stop"
c = h["additionalContext"]
assert c.startswith("keel gate failed after your changes. Fix each failing sensor below by following its guidance: block, then finish. Do not edit tests, .agents/baselines/ or .agents/state.yml to make it pass."), c
assert "guidance:" in c
assert "decision" not in d
'; check "fail: valid Stop JSON with header and guidance" $?
[ ! -e "$r/.agents/run/last-green" ]; check "fail: last-green not written" $?

# --- loop guard
echo b >> "$r/t.txt"
hook "$r" '{"stop_hook_active":true}' STUB_RC=1 STUB_OUT_FILE="$FAILOUT"
printf '%s' "$out" | python3 -c '
import sys, json
d = json.load(sys.stdin)
assert d["systemMessage"] == "keel gate is still failing with the same result; stopping the loop. Run make gate-fast to see it."
assert "hookSpecificOutput" not in d
'; check "loop guard: same failure with stop_hook_active -> systemMessage" $?
printf 'x tests [correctness] Tests 2 failed (2) 9.9s\n  guidance: other thing\n' > "$W/fail2.txt"
echo c >> "$r/t.txt"
hook "$r" '{"stop_hook_active":true}' STUB_RC=1 STUB_OUT_FILE="$W/fail2.txt"
printf '%s' "$out" | python3 -c '
import sys, json
d = json.load(sys.stdin)
assert "additionalContext" in d["hookSpecificOutput"]
'; check "different failure with stop_hook_active -> additionalContext again" $?
# same failure but different timings still counts as the same
echo d >> "$r/t.txt"; hook "$r" '{}' STUB_RC=1 STUB_OUT_FILE="$FAILOUT"
sed 's/2\.1s/7.7s/g' "$FAILOUT" > "$W/fail3.txt"; echo e >> "$r/t.txt"
hook "$r" '{"stop_hook_active":true}' STUB_RC=1 STUB_OUT_FILE="$W/fail3.txt"
printf '%s' "$out" | qgrep '"systemMessage"'; check "loop guard ignores timing differences" $?

# --- gate crash
r="$(mkrepo)"; echo a > "$r/t.txt"
hook "$r" '{}' STUB_RC=127
[ $rc -eq 0 ] && printf '%s' "$out" | python3 -c '
import sys, json
d = json.load(sys.stdin)
assert d["systemMessage"] == "keel gate could not run (scripts/gate.sh exited 127). Run make gate-fast to see why."
'; check "gate crash -> systemMessage" $?

# --- lock
r="$(mkrepo)"; echo a > "$r/t.txt"; rm -f "$W/ran"; mkdir -p "$r/.agents/run/.gate-lock"
hook "$r" '{}' STUB_RC=1 STUB_OUT_FILE="$FAILOUT"
[ -z "$out" ] && [ "$(ran)" = 0 ]; check "fresh lock: silent, gate not run" $?
touch -d '20 minutes ago' "$r/.agents/run/.gate-lock"
hook "$r" '{}' STUB_RC=1 STUB_OUT_FILE="$FAILOUT"
[ -n "$out" ] && [ "$(ran)" = 1 ] && [ ! -d "$r/.agents/run/.gate-lock" ]; check "stale lock: removed, gate runs, lock released" $?

# --- no changes (RF5)
r="$(mkrepo)"; rm -f "$W/ran"; (cd "$r" && git add -A && git commit -q -m h)
hook "$r" '{}' STUB_RC=1 STUB_OUT_FILE="$FAILOUT"
[ -z "$out" ] && [ $rc -eq 0 ] && [ "$(ran)" = 0 ]; check "clean tree: silent, gate not run" $?

# --- a commit made during the turn is still checked
r="$(mkrepo)"; echo a > "$r/t.txt"; (cd "$r" && git add -A && git commit -q -m a); rm -f "$W/ran"
hook "$r" '{}' STUB_RC=1 STUB_OUT_FILE="$FAILOUT"
[ -z "$out" ] && [ "$(ran)" = 0 ] && [ -s "$r/.agents/run/last-seen" ]; check "first look at a clean tree: recorded, silent, gate not run" $?
fa="$(cd "$r" && tree_fingerprint)"; echo b >> "$r/t.txt"; (cd "$r" && git commit -q -am b); fb="$(cd "$r" && tree_fingerprint)"
[ "$fa" != "$fb" ]; check "fingerprint changes after a commit (clean tree, new HEAD)" $?
hook "$r" '{}' STUB_RC=1 STUB_OUT_FILE="$FAILOUT"
[ "$(ran)" = 1 ] && printf '%s' "$out" | qgrep '"additionalContext"'; check "edit committed during the turn: gate runs and reports" $?
hook "$r" '{}' STUB_RC=1 STUB_OUT_FILE="$FAILOUT"
[ -z "$out" ] && [ "$(ran)" = 1 ]; check "unchanged since a failing check: silent, gate not re-run" $?
hook "$r" '{"stop_hook_active":true}' STUB_RC=1 STUB_OUT_FILE="$FAILOUT"
[ "$(ran)" = 1 ] && printf '%s' "$out" | qgrep '"systemMessage":"keel gate is still failing'; check "unchanged with stop_hook_active: loop guard, gate not re-run" $?

# --- outside git (RF5)
d="$(mktemp -d)"; _keel_tmps="$_keel_tmps $d"; mkdir -p "$d/scripts/hooks"; cp "$HOOK_SRC" "$d/scripts/hooks/"; rm -f "$W/ran"
out="$(cd "$d" && printf '{}' | GATE_RAN="$W/ran" bash scripts/hooks/claude-stop.sh 2>&1)"; rc=$?
[ -z "$out" ] && [ $rc -eq 0 ] && [ "$(ran)" = 0 ]; check "outside a git repo: silent, rc 0" $?

# --- never exit 2
r="$(mkrepo)"; echo z > "$r/t.txt"
for rcv in 0 1 2 5 127; do
  rm -rf "$r/.agents/run/last-green" "$r/.agents/run/last-fail" "$r/.agents/run/last-seen"
  hook "$r" '{}' STUB_RC=$rcv STUB_OUT_FILE="$FAILOUT"; [ $rc -eq 0 ]; check "gate rc $rcv -> hook rc 0" $?
done

# --- F6: the same sensor failing in three sessions in a row writes a lesson to .agents/run/learnings/
# session REPO ID STUB_RC [OUTFILE] -> one hook run in session ID, after a change to the tree
n_sess=0
session() {
  local r="$1" id="$2" rcv="$3" of="${4:-$FAILOUT}"
  n_sess=$((n_sess + 1)); echo "change $n_sess" >> "$r/t.txt"
  hook "$r" "{\"session_id\":\"$id\",\"stop_hook_active\":false}" STUB_RC="$rcv" STUB_OUT_FILE="$of"
}
lessons() { ls "$1/.agents/run/learnings" 2>/dev/null | grep -c '\.md$'; }
r="$(mkrepo)"; echo a > "$r/t.txt"
session "$r" s1 1; session "$r" s2 1
[ "$(lessons "$r")" = 0 ]; check "lesson: two sessions failing the same sensor write nothing" $?
session "$r" s3 1
[ $rc -eq 0 ] && [ "$(lessons "$r")" = 1 ]; check "lesson: the third session in a row writes one lesson, rc 0" $?
lf="$(ls "$r"/.agents/run/learnings/*.md 2>/dev/null | head -1)"
case "$lf" in */"$(date -u +%Y-%m-%d)"-sensor-tests-fails-every-session.md) true ;; *) false ;; esac; check "lesson: file name is YYYY-MM-DD-sensor-<id>-fails-every-session.md ($lf)" $?
[ "$(sed -n 1p "$lf" | cut -c1-8)" = "Source: " ] && [ "$(sed -n 2p "$lf")" = "Seen: 3" ] && [ "$(sed -n 3p "$lf")" = "Proposed: rule" ]; check "lesson: Source, Seen: 3 and Proposed: rule are the first three lines" $?
grep -q 'tests' "$lf" && grep -q 'fix the thing' "$lf"; check "lesson: names the sensor and carries its guidance" $?
printf '%s' "$out" | python3 -c '
import sys, json
d = json.load(sys.stdin)
assert d["hookSpecificOutput"]["additionalContext"].startswith("keel gate failed after your changes.")
'; check "lesson: the hook's own output is unchanged" $?
session "$r" s4 1
[ "$(lessons "$r")" = 1 ] && [ "$(sed -n 2p "$lf")" = "Seen: 4" ]; check "lesson: a fourth session raises Seen: and writes no second file" $?
session "$r" s4 1 "$W/fail3.txt"
[ "$(sed -n 2p "$lf")" = "Seen: 4" ]; check "lesson: the same session failing again does not count twice" $?

# a green gate run starts the count over
r="$(mkrepo)"; echo a > "$r/t.txt"
session "$r" s1 1; session "$r" s2 1; printf "v tests [correctness] Tests ok 1.0s\ngate: fast - PASSED (1 of 1)\n" > "$W/pass.txt"; session "$r" s3 0 "$W/pass.txt"; session "$r" s4 1; session "$r" s5 1
[ "$(lessons "$r")" = 0 ]; check "lesson: a passing run in between resets the streak" $?
session "$r" s6 1
[ "$(lessons "$r")" = 1 ]; check "lesson: three failing sessions after the reset write the lesson" $?

# a different sensor failing does not extend the streak of another one
printf 'x other [correctness] Other 1 failed (1) 1.0s\n  guidance: fix other\n' > "$W/other.txt"
r="$(mkrepo)"; echo a > "$r/t.txt"
session "$r" s1 1; session "$r" s2 1; session "$r" s3 1 "$W/other.txt"
[ "$(lessons "$r")" = 0 ]; check "lesson: sensors are counted separately" $?

# no session id: no lesson
r="$(mkrepo)"; echo a > "$r/t.txt"
for i in 1 2 3 4; do echo "c$i" >> "$r/t.txt"; hook "$r" '{}' STUB_RC=1 STUB_OUT_FILE="$FAILOUT"; done
[ "$(lessons "$r")" = 0 ]; check "lesson: without a session_id nothing is counted" $?

# writing a lesson never changes the hook's output or exit code
r1="$(mkrepo)"; r2="$(mkrepo)"; echo a > "$r1/t.txt"; echo a > "$r2/t.txt"
mkdir -p "$r2/.agents/run"; echo blocker > "$r2/.agents/run/learnings"
for s in s1 s2; do session "$r1" "$s" 1; session "$r2" "$s" 1; done
session "$r1" s3 1; o1="$out"; rc1=$rc
session "$r2" s3 1; o2="$out"; rc2=$rc
[ "$o1" = "$o2" ] && [ "$rc1" = 0 ] && [ "$rc2" = 0 ] && [ "$(lessons "$r1")" = 1 ]; check "lesson: an unwritable learnings folder changes neither the output nor the exit code" $?
r="$(mkrepo)"; echo a > "$r/t.txt"; mkdir -p "$r/.agents/run"; echo blocker > "$r/.agents/run/fail-streaks"
session "$r" s1 1; [ $rc -eq 0 ] && printf '%s' "$out" | grep -q '"additionalContext"'; check "lesson: an unreadable streak file does not break the hook" $?
! grep -qE 'gate\.sh +slow' "$HOOK_SRC" && ! grep -qE '(^|[^a-z])(sleep|curl|wget)( |$)' "$HOOK_SRC"; check "lesson: the hook adds no sleep and no network call (120 s timeout)" $?

# --- settings
S="$KEEL/assets/adapters/claude/settings-stop.json"
jq -e . "$S" >/dev/null 2>&1; check "settings-stop.json parses" $?
cmd="$(jq -r '.hooks.Stop[0].hooks[0].command' "$S" 2>/dev/null)"
case "$cmd" in *'${CLAUDE_PROJECT_DIR}'*scripts/hooks/claude-stop.sh*) true ;; *) false ;; esac; check "settings command uses literal CLAUDE_PROJECT_DIR and the hook path" $?
[ "$(jq -r '.hooks.Stop[0].hooks[0].timeout' "$S")" = 120 ]; check "settings timeout 120" $?
! grep -q 'exit 2' "$HOOK_SRC" && ! grep -q '"block"' "$HOOK_SRC"; check "hook never exits 2 or emits block" $?
# the Stop hook runs the fast gate only, never the slow one (rules: "never run by the Stop hook")
grep -q 'gate.sh fast' "$HOOK_SRC" && ! grep -qE 'gate\.sh +slow|gate-slow' "$HOOK_SRC"; check "Stop hook runs only the fast gate" $?
finish
