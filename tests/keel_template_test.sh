#!/usr/bin/env bash
# F2c-3 (spec 5.5): each skill follows the skill template - five headings, in order - and its
# Discipline section carries a prohibition plus a rationalization table.
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"

SKILLS="assess build rules"
for s in $SKILLS; do
  f="$KEEL/skills/$s/SKILL.md"
  got="$(grep -E '^## ' "$f" | grep -E '^## (0\. Precondition|Phases|Output contract|Discipline|Done when)$' | tr '\n' '|')"
  want='## 0. Precondition|## Phases|## Output contract|## Discipline|## Done when|'
  r=0; [ "$got" = "$want" ] || r=1
  check "$s: the five template headings, in order" $r
  grep -q '^name: '"$s"'$' "$f"; check "$s: frontmatter name" $?
  grep -q '^description: >' "$f" && grep -q 'Use when' "$f"; check "$s: description says 'Use when'" $?
  # the Discipline section holds a table whose header names the excuse (rationalization table)
  sec="$(awk '/^## Discipline$/{d=1;next} /^## /{d=0} d' "$f")"
  printf '%s\n' "$sec" | grep -qE '^\| The excuse \|'; check "$s: Discipline has a rationalization table" $?
  [ "$(printf '%s\n' "$sec" | grep -cE '^\| ["A-Za-z]' )" -ge 4 ]; check "$s: the rationalization table has at least 3 rows" $?
  # Done when names the verify command
  awk '/^## Done when$/{d=1;next} /^## /{d=0} d' "$f" | grep -qF "scripts/keel verify $s"; check "$s: Done when runs keel verify $s" $?
  # Precondition names the check
  awk '/^## 0\. Precondition$/{d=1;next} /^## /{d=0} d' "$f" | grep -qF "scripts/keel check pre $s"; check "$s: Precondition runs keel check pre $s" $?
done
grep -q '^disallowed-tools:' "$KEEL/skills/assess/SKILL.md"; check "assess (read-only) declares disallowed-tools" $?
for s in build rules; do
  ! grep -q '^disallowed-tools:' "$KEEL/skills/$s/SKILL.md"; check "$s (writes) declares no disallowed-tools" $?
done
finish
