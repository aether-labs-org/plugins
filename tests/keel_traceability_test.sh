#!/usr/bin/env bash
# D37: every `never` / `always` / `must` / "writes nothing" line in a SKILL.md has a row in the
# Traceability table of contracts/flow.md, and every target that row names exists. The number of
# rows with no check (`none`) is reported, not failed: they are the gaps the owner reads.
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
FLOW="$KEEL/contracts/flow.md"
PAT='never|Never|always|Always|\*\*Write nothing|writes nothing|must'
TAB="$(printf '\t')"

# --- the matrix: skill<TAB>quote<TAB>form<TAB>checked-by, one row per line
rows="$(awk '/^## Traceability$/{t=1;next} t&&/^## /{t=0} t&&/^\| (assess|build|rules) \|/{print}' "$FLOW" | while IFS='|' read -r _ skill rule form checked _; do
  skill="$(printf '%s' "$skill" | sed 's/^ *//;s/ *$//')"
  rule="$(printf '%s' "$rule" | sed 's/^ *"//;s/" *$//')"
  form="$(printf '%s' "$form" | sed 's/^ *//;s/ *$//')"
  checked="$(printf '%s' "$checked" | sed 's/^ *//;s/ *$//')"
  printf '%s\t%s\t%s\t%s\n' "$skill" "$rule" "$form" "$checked"
done)"
n_rows="$(printf '%s\n' "$rows" | grep -c .)"
[ "$n_rows" -ge 30 ]; check "the Traceability table has rows ($n_rows)" $?

# --- every trigger line has a row whose quote is a substring of it
total=0
for f in "$KEEL"/skills/*/SKILL.md; do
  s="$(basename "$(dirname "$f")")"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    total=$((total + 1))
    hit=1
    while IFS="$TAB" read -r rs rq _; do
      [ "$rs" = "$s" ] || continue
      case "$line" in *"$rq"*) hit=0; break ;; esac
    done <<EOL
$rows
EOL
    check "$s: has a matrix row: $(printf '%s' "$line" | cut -c1-70)" $hit
  done <<EOL
$(grep -E "$PAT" "$f")
EOL
done
[ "$total" -ge 30 ]; check "collected the never/always lines of the skills ($total)" $?

# --- no stale row: each quote matches a trigger line of its own skill
while IFS="$TAB" read -r rs rq _; do
  [ -n "$rs" ] || continue
  grep -E "$PAT" "$KEEL/skills/$rs/SKILL.md" 2>/dev/null | grep -qF -- "$rq"; check "$rs: row quote still matches a line: $rq" $?
done <<EOL
$rows
EOL

# --- forms and targets
none=0
while IFS="$TAB" read -r rs rq form checked; do
  [ -n "$rs" ] || continue
  case "$form" in recipe | slot | discipline) ok=0 ;; *) ok=1 ;; esac
  check "$rs: form is recipe, slot or discipline: $rq" $ok
  # targets are separated by "; ", each may end with a (note)
  list="$(printf '%s' "$checked" | sed 's/; /\n/g')"
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    bare="$(printf '%s' "$t" | sed 's/ (.*$//')"
    case "$bare" in
      none)
        printf '%s' "$t" | grep -qE '^none \(.+\)$'; check "$rs: none carries a written reason: $rq" $?
        none=$((none + 1)) ;;
      test:*) [ -f "$KEEL/../../${bare#test:}" ]; check "$rs: test exists: ${bare#test:}" $? ;;
      eval:*) [ -f "$KEEL/evals/${bare#eval:}" ]; check "$rs: eval grader exists: ${bare#eval:}" $? ;;
      hook:*) [ -f "$KEEL/${bare#hook:}" ]; check "$rs: hook exists: ${bare#hook:}" $? ;;
      verify:*)
        vs="$(printf '%s' "$bare" | sed -n 's/^verify:\([a-z]*\) item [0-9][0-9]*$/\1/p')"
        vn="$(printf '%s' "$bare" | sed -n 's/^verify:[a-z]* item \([0-9][0-9]*\)$/\1/p')"
        r=1
        if [ -n "$vs" ] && [ -n "$vn" ]; then
          awk -v h="**\`verify $vs" -v n="$vn" 'index($0,h)==1{t=1;next} t&&/^(\*\*|## )/{t=0} t&&index($0,"| " n " |")==1{f=1} END{exit !f}' "$FLOW" && r=0
        fi
        check "$rs: verify item exists in flow.md: ${bare#verify:}" $r ;;
      *) fail "$rs: unknown target form: $t" ;;
    esac
  done <<EOL
$list
EOL
done <<EOL
$rows
EOL
echo "  note $none rule(s) have no check (none): see the rows marked none in contracts/flow.md"
finish
