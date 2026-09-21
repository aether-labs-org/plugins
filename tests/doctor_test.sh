#!/usr/bin/env bash
set -uo pipefail
fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
root="$(cd "$(dirname "$0")/.." && pwd)"
f="$root/plugins/keel-harness/skills/doctor/SKILL.md"

grep -q "100 lines" "$f" 2>/dev/null; check "check 1: AGENTS.md size" $?
grep -qi "no longer exist" "$f" 2>/dev/null; check "check 2: stale command" $?
grep -qi "not installed\|fails to run" "$f" 2>/dev/null; check "check 3: missing sensor tool" $?
grep -q "model_baseline" "$f" 2>/dev/null; check "check 4: stale model baseline" $?
grep -qi "writes nothing" "$f" 2>/dev/null; check "doctor writes nothing" $?
grep -qi "exactly one warning" "$f" 2>/dev/null; check "one condition produces one warning" $?
# v0.2 checks must not sneak in: they need history that does not exist yet.
! grep -qi "capture rate" "$f" 2>/dev/null; check "no history-dependent checks" $?

exit $fail
