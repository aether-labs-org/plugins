#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# test-presence - heuristic rule sensor. Every changed main file matching INCLUDE must have a test at
# a path produced by one of the MAPPINGS; otherwise it counts 1. Counts are compared with
# .agents/baselines/test-presence.tsv. A file no mapping applies to is not covered by the rule.
# Env (.agents/rules/testing-strategy.env): INCLUDE (git pathspecs of main files, one per line),
# MAPPINGS (lines from_regex|to_template in sed -E syntax, e.g.
# ^src/main/java/(.*)\.java$|src/test/java/\1Test.java).
# In:  SCOPE (newline-separated changed files; empty = all). KEEL_MEASURE=1 prints baseline rows.
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=test-presence
class=heuristic
# shellcheck disable=SC1090,SC1091
. "${KEEL_BASELINE_LIB:-scripts/lib/baseline.sh}"

RULE_ENV="${RULE_ENV:-.agents/rules/testing-strategy.env}"
if [ ! -f "$RULE_ENV" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no .agents/rules/testing-strategy.env - run the rules skill"
  exit 2
fi
INCLUDE=""; EXCLUDE=""; MAPPINGS=""; ENFORCEMENT_LEVEL=""; EXCEPTIONS=""
# shellcheck disable=SC1090,SC1091
. "${KEEL_ENVPARSE_LIB:-scripts/lib/envparse.sh}" 2>/dev/null || {
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "scripts/lib/envparse.sh is missing - run /keel-harness:build"
  exit 2
}
keel_env_load_sensor "$id" "$class" "$RULE_ENV"

# --- keel:repo-specific begin ---
GUIDANCE="Write the missing test at the mapped path, for the behaviour you changed (docs/testing.md#testing-strategy). Do not create an empty test to pass, and do not add the file to .agents/baselines/test-presence.tsv."
# --- keel:repo-specific end ---

baseline=".agents/baselines/$id.tsv"
# A temp dir: TMPDIR, else .agents/run/tmp/ (git-ignored), else none.
keel_tmpdir() { mktemp -d 2>/dev/null || { mkdir -p .agents/run/tmp 2>/dev/null && mktemp -d .agents/run/tmp/XXXXXX 2>/dev/null; }; }
tmp="$(keel_tmpdir)" || tmp=""
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no writable temp directory (TMPDIR or .agents/run/tmp/)"
  exit 2
fi
trap 'rm -rf "$tmp"' EXIT

specs=()
while IFS= read -r l; do [ -n "$l" ] && specs[${#specs[@]}]="$l"; done <<LIST
$INCLUDE
LIST
while IFS= read -r l; do [ -n "$l" ] && specs[${#specs[@]}]=":(exclude)$l"; done <<LIST
$EXCLUDE
LIST
git ls-files -z --cached --others --exclude-standard -- ${specs[@]+"${specs[@]}"} | tr '\0' '\n' > "$tmp/cand"
if [ -n "${SCOPE:-}" ] && [ "${KEEL_MEASURE:-}" != 1 ]; then
  printf '%s\n' "$SCOPE" > "$tmp/scope"
  awk 'NR == FNR { s[$0] = 1; next } ($0 in s)' "$tmp/scope" "$tmp/cand" > "$tmp/cand2"
  mv "$tmp/cand2" "$tmp/cand"
fi

sep="$(printf '\001')"
checked=0
: > "$tmp/counts"; : > "$tmp/expected"
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  checked=$((checked + 1))
  applied=0; found=0; first=""
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    from="${m%%|*}"; to="${m#*|}"
    printf '%s\n' "$f" | grep -Eq -- "$from" || continue
    applied=1
    t="$(printf '%s\n' "$f" | sed -E "s${sep}${from}${sep}${to}${sep}")"
    [ -n "$first" ] || first="$t"
    if [ -f "$t" ]; then found=1; break; fi
  done <<LIST
$MAPPINGS
LIST
  if [ "$applied" -eq 1 ] && [ "$found" -eq 0 ]; then
    printf '%s\t1\n' "$f" >> "$tmp/counts"
    printf '%s\t%s\n' "$f" "$first" >> "$tmp/expected"
  else
    printf '%s\t0\n' "$f" >> "$tmp/counts"
  fi
done < "$tmp/cand"

if [ "${KEEL_MEASURE:-}" = 1 ]; then
  baseline_header
  awk -F'\t' '$2 > 0' "$tmp/counts" | LC_ALL=C sort
  exit 0
fi

# --- mandatory rules (D43): no baseline; EXCEPTIONS are skipped until their deadline, then fail ---
excepted=0
if [ "${ENFORCEMENT_LEVEL:-ratchet}" = mandatory ]; then
  baseline=/dev/null
  mandatory_exceptions "$EXCEPTIONS" "$tmp/counts"
  excepted=$(wc -l < "$tmp/counts.excepted" | tr -d ' ')
fi

over=$(awk -F'\t' '$2 > 0' "$tmp/counts" | wc -l | tr -d ' ')
held="$over baselined"; [ "${ENFORCEMENT_LEVEL:-ratchet}" != mandatory ] || held="$excepted excepted"
viol="$(baseline_compare "$baseline" "$tmp/counts")"; brc=$?
if [ "$brc" -eq 2 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no writable temp directory (TMPDIR or .agents/run/tmp/)"
  exit 2
fi
if [ "$brc" -eq 0 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "$checked files checked, all have a test ($held)."
  exit 0
fi
nv=$(printf '%s\n' "$viol" | wc -l | tr -d ' ')
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$nv of $checked files without a test."
printf '%s\n' "$viol" | head -5 | while IFS="$(printf '\t')" read -r p _ _; do
  e="$(awk -F'\t' -v p="$p" '$1 == p { print $2; exit }' "$tmp/expected")"
  printf '  %s: no test found (expected %s)\n' "$p" "$e"
done
[ -s "$tmp/counts.expired" ] && awk -F'\t' '{ printf "  %s: exception expired on %s\n", $1, $2 }' "$tmp/counts.expired" | head -5
printf '  guidance: %s\n' "$GUIDANCE"
exit 1
