#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# tests - correctness. Runs the test classes of the changed files: src/main/**/Foo.{java,kt} maps to
# FooTest when src/test/**/FooTest.{java,kt} exists; a changed test class runs itself; nothing mapped
# passes without calling the build tool. Empty SCOPE runs the whole suite.
# In:  SCOPE (newline-separated changed files; empty = whole suite).
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=tests
class=correctness

# --- keel:repo-specific begin ---
BUILD="gradle"
CMD=(./gradlew -q)
# Maven: BUILD="maven" CMD=(./mvnw -q -o)
GUIDANCE='a test that passed before now fails, so behaviour changed. Read the failing assertion above (expected vs actual), then look at what changed in the source class it exercises - git diff shows it. If that behaviour change was NOT intended, revert it in the source; do not edit the test to match the new value. If it WAS intended, update the test and record the decision as a new ADR in the folder adr_dir names in .agents/state.yml (docs/adr/ by default) - never edit an accepted one.'
# --- keel:repo-specific end ---

case "${CMD[0]}" in
  */*) [ -x "${CMD[0]}" ] && have=1 || have=0 ;;
  *) command -v "${CMD[0]}" >/dev/null 2>&1 && have=1 || have=0 ;;
esac
if [ "$have" -ne 1 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "${CMD[0]} not found - run: make bootstrap"
  exit 2
fi

classes=""
if [ -n "${SCOPE:-}" ]; then
  classes=$(printf '%s\n' "$SCOPE" | grep -E '\.(java|kt)$' | while IFS= read -r f; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"; b="${b%.*}"
    case "$f" in
      */src/test/* | src/test/*) printf '%s\n' "$b" ;;
      *) if [ -n "$(git ls-files --cached --others --exclude-standard -- "*/${b}Test.java" "*/${b}Test.kt" "${b}Test.java" "${b}Test.kt" | head -1)" ]; then printf '%sTest\n' "$b"; fi ;;
    esac
  done | sort -u)
  if [ -z "$classes" ]; then
    printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "no related test found for the changed files"
    exit 0
  fi
fi

# Quiet Gradle/Maven runs print no assertion text; the JUnit reports written by this run do.
# shellcheck disable=SC1091
[ -f scripts/lib/junit.sh ] && . scripts/lib/junit.sh
since="$(mktemp)"; trap 'rm -f "$since"' EXIT

if [ -z "$classes" ]; then
  out="$("${CMD[@]}" test 2>&1)"; rc=$?
  what="whole suite"
elif [ "$BUILD" = maven ]; then
  csv=$(printf '%s\n' "$classes" | paste -sd, -)
  out="$("${CMD[@]}" test "-Dtest=$csv" -Dsurefire.failIfNoSpecifiedTests=false 2>&1)"; rc=$?
  what="$(printf '%s\n' "$classes" | wc -l | tr -d ' ') test class(es)"
else
  args=()
  while IFS= read -r c; do args[${#args[@]}]="--tests"; args[${#args[@]}]="*$c"; done <<LIST
$classes
LIST
  out="$("${CMD[@]}" test "${args[@]}" 2>&1)"; rc=$?
  what="$(printf '%s\n' "$classes" | wc -l | tr -d ' ') test class(es)"
fi

if [ "$rc" -eq 0 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "Tests passed ($what)."
  exit 0
fi
fails=""
if type junit_failures >/dev/null 2>&1; then
  # Only the classes this run selected: Gradle rewrites the reports of earlier runs too.
  # shellcheck disable=SC2086
  fails="$(junit_failures "$since" $classes)"
fi
if [ -n "$fails" ]; then
  nf=$(printf '%s\n' "$fails" | wc -l | tr -d ' ')
  details="$fails"
else
  nf=$(printf '%s\n' "$out" | grep -cE ' FAILED$|Tests run:.*Failures: [1-9]|FAILURE!')
  details="$(printf '%s\n' "$out" | grep -E 'FAILED|AssertionFailedError|expected:|FAILURE!')"
fi
[ "$nf" -gt 0 ] || nf=1
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$nf test failure(s) ($what)."
printf '%s\n' "$details" | head -5 | sed 's/^/  /'
printf '  guidance: %s\n' "$GUIDANCE"
exit 1
