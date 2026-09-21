#!/usr/bin/env bash
# tests — correctness. Runs the tests related to the changed files.
set -uo pipefail
id=tests
class=correctness

vitest="node_modules/.bin/vitest"
if [ ! -x "$vitest" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "vitest is not installed - run: make bootstrap"
  exit 2
fi

changed=$(printf '%s\n' "${SCOPE:-}" | sed '/^$/d' | grep -E '\.(ts|tsx|js|jsx)$')
if [ -n "$changed" ]; then
  # shellcheck disable=SC2086
  out="$("$vitest" related --run $changed 2>&1)"; rc=$?
else
  out="$("$vitest" run 2>&1)"; rc=$?
fi

line=$(printf '%s\n' "$out" | grep -E '^ *Tests +' | tail -1 | sed 's/^ *//')
[ -n "$line" ] || line="no related test found for the changed files"

if [ "$rc" -eq 0 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "$line"
  exit 0
fi

printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$line"
printf '%s\n' "$out" | grep -E 'FAIL|AssertionError|expected' | head -6 | sed 's/^/  /'
printf '  guidance: a test that passed before now fails, so behaviour changed. Read the failing\n'
printf '  assertion above (expected vs received), then look at what changed in the source file it\n'
printf '  exercises - `git diff` shows it. If that behaviour change was NOT intended, revert it in\n'
printf '  the source; do not edit the test to match the new number. If it WAS intended, update the\n'
printf '  test and record the decision in docs/decisions/ as a new ADR - never edit an accepted one.\n'
exit 1
