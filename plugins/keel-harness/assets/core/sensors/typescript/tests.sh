#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# tests - correctness. Runs the tests related to the changed files (whole suite when SCOPE is empty).
# In:  SCOPE (newline-separated changed files; empty = whole repo).
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=tests
class=correctness

# --- keel:repo-specific begin ---
RUNNER="vitest"
BIN="node_modules/.bin/vitest"
GUIDANCE='a test that passed before now fails, so behaviour changed. Read the failing assertion above (expected vs received), then look at what changed in the source file it exercises - git diff shows it. If that behaviour change was NOT intended, revert it in the source; do not edit the test to match the new number. If it WAS intended, update the test and record the decision as a new ADR in the folder adr_dir names in .agents/state.yml (docs/adr/ by default) - never edit an accepted one.'
# --- keel:repo-specific end ---

if [ ! -x "$BIN" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "$RUNNER is not installed - run: make bootstrap"
  exit 2
fi

changed=""
if [ -n "${SCOPE:-}" ]; then
  changed=$(printf '%s\n' "$SCOPE" | grep -E '\.(ts|tsx|js|jsx)$' | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done)
  if [ -z "$changed" ]; then
    printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "no related test found for the changed files"
    exit 0
  fi
fi

if [ -n "$changed" ]; then
  if [ "$RUNNER" = jest ]; then
    out="$(printf '%s\n' "$changed" | tr '\n' '\0' | xargs -0 "$BIN" --passWithNoTests --findRelatedTests 2>&1)"; rc=$?
  else
    out="$(printf '%s\n' "$changed" | tr '\n' '\0' | xargs -0 "$BIN" related --run 2>&1)"; rc=$?
  fi
elif [ "$RUNNER" = jest ]; then
  out="$("$BIN" --ci 2>&1)"; rc=$?
else
  out="$("$BIN" run 2>&1)"; rc=$?
fi

line=$(printf '%s\n' "$out" | grep -E '^ *Tests:? +' | tail -1 | sed 's/^ *//')
[ -n "$line" ] || line="no related test found for the changed files"

if [ "$rc" -eq 0 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "$line"
  exit 0
fi

printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$line"
printf '%s\n' "$out" | grep -E 'FAIL|AssertionError|expected' | head -5 | sed 's/^/  /'
printf '  guidance: %s\n' "$GUIDANCE"
exit 1
