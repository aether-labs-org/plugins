#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# tests - correctness. Runs the pytest tests mapped from the changed files (the whole suite when
# SCOPE is empty). a/b/mod.py maps to TEST_ROOT/**/test_mod.py or **/mod_test.py; a changed test
# file runs itself; nothing mapped passes without calling pytest.
# In:  SCOPE (newline-separated changed files; empty = whole suite).
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=tests
class=correctness

# --- keel:repo-specific begin ---
CMD=(.venv/bin/pytest -q)
TEST_ROOT="tests"
GUIDANCE='a test that passed before now fails, so behaviour changed. Read the failing assertion above (expected vs received), then look at what changed in the source file it exercises - git diff shows it. If that behaviour change was NOT intended, revert it in the source; do not edit the test to match the new value. If it WAS intended, update the test and record the decision in docs/decisions/ as a new ADR - never edit an accepted one.'
# --- keel:repo-specific end ---

case "${CMD[0]}" in
  */*) [ -x "${CMD[0]}" ] && have=1 || have=0 ;;
  *) command -v "${CMD[0]}" >/dev/null 2>&1 && have=1 || have=0 ;;
esac
if [ "$have" -ne 1 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "pytest is not installed - run: make bootstrap"
  exit 2
fi

mapped=""
if [ -n "${SCOPE:-}" ]; then
  mapped=$(printf '%s\n' "$SCOPE" | grep -E '\.py$' | while IFS= read -r f; do
    [ -f "$f" ] || continue
    b="$(basename "$f" .py)"
    case "$b" in
      test_* | *_test) printf '%s\n' "$f" ;;
      *) find "$TEST_ROOT" \( -name "test_$b.py" -o -name "${b}_test.py" \) -type f 2>/dev/null ;;
    esac
  done | sort -u)
  if [ -z "$mapped" ]; then
    printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "no related test found for the changed files"
    exit 0
  fi
fi

if [ -n "$mapped" ]; then
  out="$(printf '%s\n' "$mapped" | tr '\n' '\0' | xargs -0 "${CMD[@]}" 2>&1)"; rc=$?
else
  out="$("${CMD[@]}" 2>&1)"; rc=$?
fi

line=$(printf '%s\n' "$out" | grep -E '[0-9]+ (passed|failed|error)' | tail -1 | sed 's/^[ =]*//; s/[ =]*$//')
[ -n "$line" ] || line="no related test found for the changed files"

if [ "$rc" -eq 0 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "$line"
  exit 0
fi
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$line"
printf '%s\n' "$out" | grep -E '^FAILED |^E  |AssertionError' | head -5 | sed 's/^/  /'
printf '  guidance: %s\n' "$GUIDANCE"
exit 1
