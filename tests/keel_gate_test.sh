#!/usr/bin/env bash
set -uo pipefail
qgrep() { grep "$@" >/dev/null; } # reads all its input: `| grep -q` can SIGPIPE the writer under pipefail
. "$(dirname "$0")/keel_helpers.sh"

# mkrepo [--no-commit] -> repo with gate.sh + gate.env installed
mkrepo() {
  local r; r="$(new_repo "$@")"
  install_asset "$r" assets/core/gate.sh scripts/gate.sh
  mkdir -p "$r/.agents" "$r/scripts/sensors"
  cp "$KEEL/assets/core/gate.env" "$r/.agents/gate.env"
  printf '%s\n' "$r"
}
# stub_sensor REPO RELPATH ID CLASS STATUS SUMMARY RC [BODY]
stub_sensor() {
  local f="$1/$2"; mkdir -p "$(dirname "$f")"
  { echo '#!/usr/bin/env bash'
    printf "printf '%%s\\\\t%%s\\\\t%%s\\\\t%%s\\\\n' '%s' '%s' '%s' '%s'\n" "$3" "$4" "$5" "$6"
    [ -n "${8:-}" ] && printf '%s\n' "$8"
    echo "exit $7"; } > "$f"
}

[ -f "$KEEL/assets/core/gate.sh" ]; check "gate.sh exists" $?
grep -q 'CEILING_SECONDS=30' "$KEEL/assets/core/gate.env" 2>/dev/null && grep -q 'SLOW_CEILING_SECONDS=600' "$KEEL/assets/core/gate.env" 2>/dev/null; check "gate.env defaults" $?
head -2 "$KEEL/assets/core/gate.sh" 2>/dev/null | qgrep '^# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.$'; check "gate.sh managed header" $?

r="$(mkrepo)"
stub_sensor "$r" scripts/sensors/a.sh a correctness pass "ok a" 0
stub_sensor "$r" scripts/sensors/b.sh b heuristic pass "ok b" 0
out="$(cd "$r" && bash scripts/gate.sh 2>&1)"; rc=$?
[ $rc -eq 0 ]; check "two pass: rc 0" $?
printf '%s\n' "$out" | qgrep -E 'gate: fast - PASSED \(2 of 2\) \| ceiling 30s, spent [0-9.]+m?s \| model cost: US\$0\.00'; check "two pass: verdict line" $?

r="$(mkrepo)"
stub_sensor "$r" scripts/sensors/a.sh a correctness pass "ok" 0
stub_sensor "$r" scripts/sensors/b.sh b correctness fail "bad" 1 "echo '  detail'; echo '  guidance: do X'"
out="$(cd "$r" && bash scripts/gate.sh 2>&1)"; rc=$?
[ $rc -eq 1 ]; check "fail: rc 1" $?
printf '%s\n' "$out" | qgrep 'FAILED (1 of 2)'; check "fail: verdict" $?
printf '%s\n' "$out" | qgrep 'guidance: do X'; check "fail: guidance in stdout" $?

r="$(mkrepo)"
stub_sensor "$r" scripts/sensors/a.sh a correctness skip "no tool" 2
stub_sensor "$r" scripts/sensors/b.sh b correctness pass "ok" 0
out="$(cd "$r" && bash scripts/gate.sh 2>&1)"
printf '%s\n' "$out" | qgrep -F 'PASSED (1 of 1, 1 skipped)'; check "skip + pass verdict" $?

# CRLF gate.env and over ceiling (RF4)
r="$(mkrepo)"
printf 'CEILING_SECONDS=1\r\nSLOW_CEILING_SECONDS=600\r\n' > "$r/.agents/gate.env"
stub_sensor "$r" scripts/sensors/a.sh a correctness pass "slow" 0 "sleep 1.2"
out="$(cd "$r" && bash scripts/gate.sh 2>&1)"; rc=$?
printf '%s\n' "$out" | qgrep -F 'ceiling 1s,'; check "CRLF env: ceiling parsed" $?
printf '%s\n' "$out" | qgrep -F '(over ceiling)'; check "over ceiling flagged" $?
[ $rc -eq 0 ]; check "over ceiling still rc 0" $?

# stray files (RF3)
r="$(mkrepo)"
stub_sensor "$r" scripts/sensors/a.sh a correctness pass "ok" 0
echo 'x' > "$r/scripts/sensors/README.md"
stub_sensor "$r" scripts/sensors/_util.sh _util correctness pass "no" 0 "touch \"\$PWD/.marker_util\""
stub_sensor "$r" scripts/sensors/disabled/x.sh x correctness pass "no" 0 "touch \"\$PWD/.marker_disabled\""
mkdir -p "$r/scripts/sensors/stoplists"; echo word > "$r/scripts/sensors/stoplists/pt.txt"
stub_sensor "$r" scripts/sensors/slow/s.sh s correctness pass "no" 0 "touch \"\$PWD/.marker_slow\""
out="$(cd "$r" && bash scripts/gate.sh 2>&1)"
printf '%s\n' "$out" | qgrep -F 'PASSED (1 of 1)'; check "only top-level non-underscore .sh run" $?
[ ! -e "$r/.marker_util" ] && [ ! -e "$r/.marker_disabled" ] && [ ! -e "$r/.marker_slow" ]; check "no marker files written" $?

# slow mode
r="$(mkrepo)"
stub_sensor "$r" scripts/sensors/a.sh a correctness pass "fast" 0 "touch \"\$PWD/.marker_fast\""
stub_sensor "$r" scripts/sensors/slow/s.sh s correctness pass "slow one" 0
out="$(cd "$r" && bash scripts/gate.sh slow 2>&1)"; rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | qgrep -E 'gate: slow - PASSED \(1 of 1\) \| ceiling 600s'; check "slow verdict and ceiling" $?
[ ! -e "$r/.marker_fast" ]; check "slow does not run fast sensors" $?
[ -f "$r/.agents/run/last-run-slow.log" ]; check "slow log written" $?
(cd "$r" && bash scripts/gate.sh bogus >/dev/null 2>&1); [ $? -eq 64 ]; check "bogus mode rc 64" $?
(cd /tmp && bash "$r/scripts/gate.sh" >/dev/null 2>&1); [ $? -eq 0 ]; check "runs from any cwd" $?

# SCOPE
r="$(mkrepo)"
echo 1 > "$r/x.ts"; echo 1 > "$r/z.ts"; (cd "$r" && git add x.ts z.ts && git commit -q -m x)
rm "$r/x.ts"; echo 2 > "$r/y.ts"; echo 2 >> "$r/z.ts"; echo 3 > "$r/my file ação.ts"
mkdir -p "$r/.agents/run/.gate-lock"; echo f > "$r/.agents/run/last-seen"; echo f > "$r/.agents/run/last-fail"; echo n > "$r/.agents/notes.md"
stub_sensor "$r" scripts/sensors/a.sh a correctness pass "ok" 0 "printf '%s\\n' \"\$SCOPE\" > \"\$PWD/scope.out\""
(cd "$r" && bash scripts/gate.sh >/dev/null 2>&1)
grep -qx 'y.ts' "$r/scope.out" && grep -qx 'z.ts' "$r/scope.out" && ! grep -qx 'x.ts' "$r/scope.out"; check "SCOPE excludes deleted, includes untracked" $?
grep -qx 'my file ação.ts' "$r/scope.out"; check "SCOPE keeps spaces and non-ASCII (RF1)" $?
! grep -qE '^\.agents/(last-|\.gate-lock)' "$r/scope.out" && grep -qx '.agents/notes.md' "$r/scope.out"; check "SCOPE leaves out keel's own run state, not other .agents files" $?

# no commits (RF2)
r="$(mkrepo --no-commit)"
stub_sensor "$r" scripts/sensors/a.sh a correctness pass "ok" 0
echo 1 > "$r/new.ts"
out="$(cd "$r" && bash scripts/gate.sh 2>&1)"; rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | qgrep 'scope: whole repository'; check "no commits: whole repo, rc 0" $?

# truncation
r="$(mkrepo)"
stub_sensor "$r" scripts/sensors/a.sh a correctness fail "many" 1 "for i in \$(seq 1 60); do echo \"  line \$i\"; done"
out="$(cd "$r" && bash scripts/gate.sh 2>&1)"
[ "$(printf '%s\n' "$out" | tail -1)" = "output truncated at 40 lines - full log in .agents/run/last-run.log" ]; check "truncation notice" $?
finish
