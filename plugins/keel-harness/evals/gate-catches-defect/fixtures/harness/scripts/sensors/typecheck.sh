#!/usr/bin/env bash
# typecheck — correctness. Wrapper protocol: see the kit's sensor contract.
# In:  SCOPE (newline-separated changed files; empty = whole repo).
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=typecheck
class=correctness

tsc="node_modules/.bin/tsc"
if [ ! -x "$tsc" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "tsc is not installed - run: make bootstrap"
  exit 2
fi

# tsc has no per-file mode under a project config: this sensor is whole-repo by nature.
out="$("$tsc" --noEmit -p tsconfig.json 2>&1)"; rc=$?
files=$(git ls-files '*.ts' '*.tsx' | wc -l | tr -d ' ')

if [ "$rc" -eq 0 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "Found 0 errors in $files files."
  exit 0
fi

n=$(printf '%s\n' "$out" | grep -cE 'error TS')
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "Found $n type error(s) in $files files."
printf '%s\n' "$out" | grep -E 'error TS' | head -5 | sed 's/^/  /'
printf '  guidance: fix the FIRST error listed above and re-run; the ones below it are usually\n'
printf '  its cascade. If the type is genuinely unknowable at that point, model the absence\n'
printf '  (undefined, a union, a narrowing check) rather than widening it to `any` - `any` makes\n'
printf '  this sensor blind to every future change in that file.\n'
exit 1
