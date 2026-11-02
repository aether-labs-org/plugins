#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# typecheck - correctness. Whole repo: tsc has no per-file mode under a project config.
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=typecheck
class=correctness

# --- keel:repo-specific begin ---
TSC="node_modules/.bin/tsc"
TSC_ARGS="--noEmit -p tsconfig.json"
GUIDANCE='fix the FIRST error listed above and re-run; the ones below it are usually its cascade. If the type is genuinely unknowable at that point, model the absence (undefined, a union, a narrowing check) rather than widening it to any - any makes this sensor blind to every future change in that file.'
# --- keel:repo-specific end ---

if [ ! -x "$TSC" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "tsc is not installed - run: make bootstrap"
  exit 2
fi

# shellcheck disable=SC2086
out="$("$TSC" $TSC_ARGS 2>&1)"; rc=$?
files=$(git ls-files '*.ts' '*.tsx' | wc -l | tr -d ' ')

if [ "$rc" -eq 0 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "Found 0 errors in $files files."
  exit 0
fi

n=$(printf '%s\n' "$out" | grep -cE 'error TS')
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "Found $n type error(s) in $files files."
printf '%s\n' "$out" | grep -E 'error TS' | head -5 | sed 's/^/  /'
printf '  guidance: %s\n' "$GUIDANCE"
exit 1
