#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# mutation - slow-gate correctness sensor. Runs mutation testing on the changed main files only and
# fails when the mutation score is under MUTATION_MIN_SCORE. Engines: pit (JVM), stryker (TS/React),
# mutmut (Python). Never run by the Stop hook; run it with make gate-slow.
# Env (.agents/rules/testing-strategy.env): MUTATION_MIN_SCORE, INCLUDE (optional pathspecs).
# In:  SCOPE (newline-separated changed files). Empty or no main source file changed -> skip.
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=mutation
class=correctness

RULE_ENV="${RULE_ENV:-.agents/rules/testing-strategy.env}"
if [ ! -f "$RULE_ENV" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no .agents/rules/testing-strategy.env - run the rules skill"
  exit 2
fi
MUTATION_MIN_SCORE=""; INCLUDE=""
# shellcheck disable=SC1090,SC1091
. "${KEEL_ENVPARSE_LIB:-scripts/lib/envparse.sh}" 2>/dev/null || {
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "scripts/lib/envparse.sh is missing - run /keel-harness:build"
  exit 2
}
keel_env_load_sensor "$id" "$class" "$RULE_ENV"
: "${MUTATION_MIN_SCORE:=60}"

# --- keel:repo-specific begin ---
ENGINE="pit"
CMD=(./mvnw -q org.pitest:pitest-maven:mutationCoverage)
# other engines: ENGINE="stryker" CMD=(node_modules/.bin/stryker run)
#                ENGINE="mutmut"  CMD=(.venv/bin/mutmut)
# Gradle: CMD=(./gradlew -q pitest) and pass the classes your pitest plugin expects.
GUIDANCE="Surviving mutants mean a test does not check that behaviour: read the surviving mutations of the changed files, then add the missing assertion (docs/testing.md#testing-strategy). Never lower MUTATION_MIN_SCORE in .agents/rules/testing-strategy.env to make this pass."
# --- keel:repo-specific end ---

[ -n "${SCOPE:-}" ] || { printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no changed source files"; exit 2; }
case "${CMD[0]}" in
  */*) [ -x "${CMD[0]}" ] && have=1 || have=0 ;;
  *) command -v "${CMD[0]}" >/dev/null 2>&1 && have=1 || have=0 ;;
esac
if [ "$have" -ne 1 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "${CMD[0]} not found ($ENGINE) - run: make bootstrap"
  exit 2
fi

# changed main source files for the engine
case "$ENGINE" in
  pit) ext='\.(java|kt)$' ;;
  stryker) ext='\.(ts|tsx|js|jsx)$' ;;
  mutmut) ext='\.py$' ;;
  *) ext='.' ;;
esac
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
git ls-files -z --cached --others --exclude-standard -- ${specs[@]+"${specs[@]}"} | tr '\0' '\n' > "$tmp/cand"
printf '%s\n' "$SCOPE" > "$tmp/scope"
awk 'NR == FNR { s[$0] = 1; next } ($0 in s)' "$tmp/scope" "$tmp/cand" \
  | grep -E -- "$ext" | grep -vE '(^|/)(test|tests|__tests__)/|\.(test|spec)\.|(^|/)test_|_test\.py$|(Test|Tests|IT)\.(java|kt)$' \
  | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done > "$tmp/targets"
[ -s "$tmp/targets" ] || { printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no changed source files"; exit 2; }

case "$ENGINE" in
  pit)
    classes=$(sed -E 's#^.*src/main/(java|kotlin)/##; s#\.(java|kt)$##; s#/#.#g' "$tmp/targets" | paste -sd, -)
    out="$("${CMD[@]}" "-DtargetClasses=$classes" 2>&1)"; rc=$?
    score=$(printf '%s\n' "$out" | sed -n 's/.*Generated [0-9]* mutations Killed [0-9]* (\([0-9]*\)%).*/\1/p' | tail -1) ;;
  stryker)
    files=$(paste -sd, - < "$tmp/targets")
    out="$("${CMD[@]}" --mutate "$files" 2>&1)"; rc=$?
    score=$(printf '%s\n' "$out" | sed -n 's/.*Final mutation score of \([0-9.]*\).*/\1/p' | tail -1) ;;
  mutmut)
    files=$(paste -sd, - < "$tmp/targets")
    out1="$("${CMD[@]}" run --paths-to-mutate "$files" 2>&1)"; rc=$?
    out2="$("${CMD[@]}" results 2>&1)"
    out="$out1
$out2"
    killed=$(printf '%s\n' "$out" | sed -n 's/.*Killed[^(]*(\([0-9]*\)).*/\1/p' | tail -1)
    survived=$(printf '%s\n' "$out" | sed -n 's/.*Survived[^(]*(\([0-9]*\)).*/\1/p' | tail -1)
    : "${killed:=0}" "${survived:=0}"
    if [ $((killed + survived)) -gt 0 ]; then score=$(awk -v k="$killed" -v s="$survived" 'BEGIN { printf "%d", k * 100 / (k + s) }'); else score=""; fi ;;
  *) out=""; rc=1; score="" ;;
esac

if [ -z "$score" ]; then
  if [ "$rc" -eq 0 ]; then
    printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "no mutations generated for the changed files ($ENGINE)."
    exit 0
  fi
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$ENGINE failed before reporting a score (exit $rc)."
  printf '%s\n' "$out" | tail -5 | sed 's/^/  /'
  printf '  guidance: %s\n' "Run the mutation command by hand and fix what it reports; the score cannot be read until it runs."
  exit 1
fi
if awk -v s="$score" -v m="$MUTATION_MIN_SCORE" 'BEGIN { exit !(s + 0 < m + 0) }'; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "mutation score ${score}% is below the minimum ${MUTATION_MIN_SCORE}% ($ENGINE)."
  printf '%s\n' "$out" | grep -iE 'survived|SURVIVED' | head -5 | sed 's/^/  /'
  printf '  guidance: %s\n' "$GUIDANCE"
  exit 1
fi
printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "mutation score ${score}% (minimum ${MUTATION_MIN_SCORE}%, $ENGINE)."
exit 0
