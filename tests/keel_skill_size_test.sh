#!/usr/bin/env bash
# D38: every SKILL.md stays under 20,000 bytes; build/SKILL.md also stays within 250 lines.
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
n=0
for f in "$KEEL"/skills/*/SKILL.md; do
  n=$((n + 1))
  b="$(wc -c < "$f" | tr -d ' ')"; s="$(basename "$(dirname "$f")")"
  [ "$b" -lt 20000 ]; check "$s/SKILL.md is under 20,000 bytes ($b)" $?
done
[ "$n" -ge 3 ]; check "found the SKILL.md files ($n)" $?
l="$(wc -l < "$KEEL/skills/build/SKILL.md" | tr -d ' ')"
[ "$l" -le 250 ]; check "build/SKILL.md is at most 250 lines ($l)" $?
finish
