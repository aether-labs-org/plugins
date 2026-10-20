#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
SD=build/assets/sensors

# mk -> repo with baseline lib and the four sensors installed
mk() {
  local r; r="$(new_repo)"
  install_asset "$r" build/assets/lib/baseline.sh scripts/lib/baseline.sh
  for s in typecheck lint tests; do install_asset "$r" "$SD/typescript/$s.sh" "scripts/sensors/$s.sh"; done
  install_asset "$r" "$SD/common/secrets.sh" scripts/sensors/secrets.sh
  mkdir -p "$r/.agents/baselines" "$r/src"
  printf '%s\n' "$r"
}
run() { # run REPO SENSOR [env...] -> sets out, rc
  local r="$1" s="$2"; shift 2
  out="$(cd "$r" && env STUB_LOG="$r/stub.log" "$@" bash "scripts/sensors/$s.sh" 2>&1)"; rc=$?
}

# --- structure
for s in typescript/typecheck typescript/lint typescript/tests common/secrets; do
  f="$KEEL/skills/$SD/$s.sh"; b="$(basename "$s")"
  [ -f "$f" ]; check "$b exists" $?
  sed -n 2p "$f" | grep -q '^# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.$'; check "$b managed header" $?
  grep -q '^# --- keel:repo-specific begin ---$' "$f" && grep -q '^# --- keel:repo-specific end ---$' "$f"; check "$b markers" $?
  grep -q "^id=$b\$" "$f"; check "$b id equals file name" $?
done
! grep -q baseline "$KEEL/skills/$SD/common/secrets.sh"; check "secrets never mentions baseline" $?

# --- skip when tool missing
r="$(mk)"
for s in typecheck lint tests; do
  run "$r" $s; [ $rc -eq 2 ] && printf '%s\n' "$out" | head -1 | grep -q "^$s	.*	skip	.*make bootstrap"; check "$s skips without tool" $?
done
sed -i 's/^GITLEAKS="gitleaks"/GITLEAKS="no-such-gitleaks-bin"/' "$r/scripts/sensors/secrets.sh"
run "$r" secrets; [ $rc -eq 2 ] && printf '%s\n' "$out" | head -1 | grep -q 'skip	.*install gitleaks'; check "secrets skips without gitleaks" $?

# --- typecheck
r="$(mk)"; use_stub "$r" tsc node_modules/.bin/tsc
echo 1 > "$r/src/a.ts"; (cd "$r" && git add -A && git commit -q -m a)
run "$r" typecheck STUB_OUT=""
[ $rc -eq 0 ]; check "typecheck pass rc" $?
[ "$(printf '%s\n' "$out" | head -1)" = "$(printf 'typecheck\tcorrectness\tpass\tFound 0 errors in 1 files.')" ]; check "typecheck pass line 1" $?
grep -q -- '--noEmit -p tsconfig.json' "$r/stub.log"; check "typecheck default args" $?
run "$r" typecheck STUB_EXIT=1 STUB_OUT=$'src/a.ts(1,1): error TS2322: bad\nsrc/a.ts(2,1): error TS2304: worse'
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q '^typecheck	correctness	fail	'; check "typecheck fail line 1" $?
[ "$(printf '%s\n' "$out" | grep -c '^  src/a.ts')" -eq 2 ] && printf '%s\n' "$out" | grep -q '^  guidance: '; check "typecheck 2 details + guidance" $?

# --- lint
r="$(mk)"; use_stub "$r" eslint node_modules/.bin/eslint
echo 1 > "$r/src/a.ts"; (cd "$r" && git add -A && git commit -q -m a)
JSON="[{\"filePath\":\"$r/src/a.ts\",\"messages\":[{\"ruleId\":\"no-console\"},{\"ruleId\":\"no-unused-vars\"}]}]"
printf '# measured_at: 2026-10-20 review_by: 2027-04-20\nsrc/a.ts\t2\n' > "$r/.agents/baselines/lint.tsv"
run "$r" lint STUB_OUT="$JSON"; [ $rc -eq 0 ] && printf '%s\n' "$out" | head -1 | grep -q '^lint	heuristic	pass	'; check "lint passes against baseline 2" $?
printf '# h\nsrc/a.ts\t1\n' > "$r/.agents/baselines/lint.tsv"
run "$r" lint STUB_OUT="$JSON" STUB_EXIT=1; [ $rc -eq 1 ] && printf '%s\n' "$out" | grep -q 'src/a.ts: 2 problems (allowed 1)'; check "lint fails against baseline 1" $?
printf '%s\n' "$out" | grep -q '^  guidance: '; check "lint fail has guidance" $?
rm "$r/.agents/baselines/lint.tsv"
run "$r" lint STUB_OUT="$JSON" STUB_EXIT=1; [ $rc -eq 1 ]; check "lint fails without baseline" $?
: > "$r/stub.log"
run "$r" lint SCOPE=src/a.ts STUB_OUT="$JSON"
grep -qx -- '-f json src/a.ts' "$r/stub.log"; check "lint passes SCOPE files to eslint" $?
: > "$r/stub.log"; run "$r" lint STUB_OUT="$JSON"; grep -qx -- '-f json src' "$r/stub.log"; check "lint empty SCOPE uses LINT_PATHS" $?
run "$r" lint KEEL_MEASURE=1 KEEL_TODAY=2026-10-20 STUB_OUT="$JSON"
[ "$out" = "$(printf '# measured_at: 2026-10-20 review_by: 2027-04-20\nsrc/a.ts\t2')" ]; check "lint KEEL_MEASURE output" $?
run "$r" lint SCOPE=README.md STUB_OUT="$JSON"; [ $rc -eq 0 ]; check "lint with no JS/TS in scope passes" $?
# ESLint 9 reports an ignored file as a ruleId-less, non-fatal warning: not a problem.
IGN="[{\"filePath\":\"$r/src/a.ts\",\"messages\":[{\"ruleId\":null,\"fatal\":false,\"severity\":1,\"message\":\"File ignored because of a matching ignore pattern.\"}]}]"
rm -f "$r/.agents/baselines/lint.tsv"
run "$r" lint SCOPE=src/a.ts STUB_OUT="$IGN"; [ $rc -eq 0 ]; check "lint ignores ESLint's file-ignored warning" $?
FATAL="[{\"filePath\":\"$r/src/a.ts\",\"messages\":[{\"ruleId\":null,\"fatal\":true,\"severity\":2,\"message\":\"Parsing error\"}]}]"
run "$r" lint SCOPE=src/a.ts STUB_OUT="$FATAL" STUB_EXIT=1; [ $rc -eq 1 ]; check "lint counts a fatal parse error" $?

# --- tests
r="$(mk)"; use_stub "$r" vitest node_modules/.bin/vitest
echo 1 > "$r/src/a.ts"; (cd "$r" && git add -A && git commit -q -m a)
run "$r" tests SCOPE=src/a.ts STUB_OUT="      Tests  3 passed (3)"
[ $rc -eq 0 ] && grep -qx 'related --run src/a.ts' "$r/stub.log"; check "tests vitest related" $?
printf '%s\n' "$out" | head -1 | grep -q '^tests	correctness	pass	Tests  3 passed (3)$'; check "tests pass line 1" $?
: > "$r/stub.log"; run "$r" tests; grep -qx 'run' "$r/stub.log"; check "tests empty SCOPE -> run" $?
run "$r" tests SCOPE=src/a.ts STUB_EXIT=1 STUB_OUT=$'      Tests  1 failed (1)\n FAIL  src/a.test.ts > x\nAssertionError: expected 1 to be 2'
[ $rc -eq 1 ] && printf '%s\n' "$out" | grep -q '^  guidance: .*docs/decisions/'; check "tests fail + guidance cites docs/decisions" $?
r2="$(mk)"; use_stub "$r2" jest node_modules/.bin/jest; echo 1 > "$r2/src/a.ts"
sed -i 's/^RUNNER="vitest"/RUNNER="jest"/; s#node_modules/.bin/vitest#node_modules/.bin/jest#' "$r2/scripts/sensors/tests.sh"
run "$r2" tests SCOPE=src/a.ts; grep -qx -- '--passWithNoTests --findRelatedTests src/a.ts' "$r2/stub.log"; check "tests jest findRelatedTests, passing when no test is related" $?

# --- secrets
r="$(mk)"; mkdir -p "$r/bin"; use_stub "$r" gitleaks bin/gitleaks
echo 1 > "$r/src/a.ts"; echo 1 > "$r/src/b.ts"
run "$r" secrets PATH="$r/bin:$PATH" SCOPE=$'src/a.ts\nsrc/b.ts'
[ $rc -eq 0 ] && [ "$(grep -c '^dir ' "$r/stub.log")" -eq 2 ]; check "secrets one dir call per SCOPE file" $?
grep -qx 'dir src/a.ts --no-banner --exit-code 1' "$r/stub.log"; check "secrets args" $?
: > "$r/stub.log"; run "$r" secrets PATH="$r/bin:$PATH"; grep -qx 'dir src --no-banner --exit-code 1' "$r/stub.log"; check "secrets empty SCOPE -> dir src" $?
run "$r" secrets PATH="$r/bin:$PATH" SCOPE=src/a.ts STUB_EXIT=1
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q '^secrets	security	fail	' && printf '%s\n' "$out" | grep -q '^  guidance: '; check "secrets fail" $?
finish
