#!/usr/bin/env bash
set -uo pipefail
fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
root="$(cd "$(dirname "$0")/.." && pwd)"
sk="$root/plugins/keel-harness/skills/assess"

[ -f "$sk/references/rubric.md" ]; check "rubric.md exists" $?
for axis in "Bootstrap" "Guides" "Fast sensors" "Slow sensors" "Enforcement" "Context"; do
  grep -q "$axis" "$sk/references/rubric.md" 2>/dev/null; check "rubric has axis: $axis" $?
done
for state in present partial absent; do
  grep -qi "$state" "$sk/references/rubric.md" 2>/dev/null; check "rubric has state: $state" $?
done
[ -f "$sk/references/harness-model.md" ]; check "harness-model.md copied" $?
grep -q "Cost to close" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md pins the report table header" $?
grep -q "setup minutes" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md names the setup-minutes unit" $?
grep -q "not measured" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md forbids guessing a cost" $?
grep -qi "writes nothing" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md states the no-write rule" $?
grep -q "aggregate score" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md forbids an aggregate score" $?

exit $fail
