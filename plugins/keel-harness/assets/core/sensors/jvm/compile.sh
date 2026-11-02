#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# compile - correctness. Whole repo: the compiler is the type checker. Usually the slowest sensor on
# the JVM; build measures it and leaves it out of the fast gate when it blows the budget.
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=compile
class=correctness

# --- keel:repo-specific begin ---
CMD=(./gradlew -q compileJava compileKotlin)
# Maven: CMD=(./mvnw -q -o compile)
GUIDANCE='fix the FIRST error listed above and re-run; the ones below it are usually its cascade. Do not silence the compiler with unchecked casts, @SuppressWarnings or !! to make this pass: model the absence (Optional, a nullable type) instead.'
# --- keel:repo-specific end ---

case "${CMD[0]}" in
  */*) [ -x "${CMD[0]}" ] && have=1 || have=0 ;;
  *) command -v "${CMD[0]}" >/dev/null 2>&1 && have=1 || have=0 ;;
esac
if [ "$have" -ne 1 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "${CMD[0]} not found - run: make bootstrap"
  exit 2
fi

out="$("${CMD[@]}" 2>&1)"; rc=$?
files=$(git ls-files '*.java' '*.kt' | wc -l | tr -d ' ')
if [ "$rc" -eq 0 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "Compiled $files source files with no errors."
  exit 0
fi

n=$(printf '%s\n' "$out" | grep -cE '^e: |: error:')
[ "$n" -gt 0 ] || n=1
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "Found $n compile error(s) in $files source files."
{ printf '%s\n' "$out" | grep -E '^e: |: error:' | head -5; [ "$n" -eq 1 ] && printf '%s\n' "$out" | grep -vE '^e: |: error:' | head -3; } | head -5 | sed 's/^/  /'
printf '  guidance: %s\n' "$GUIDANCE"
exit 1
