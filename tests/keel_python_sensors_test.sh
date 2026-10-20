#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
SD=build/assets/sensors/python
mk() {
  local r; r="$(new_repo)"
  install_asset "$r" build/assets/lib/baseline.sh scripts/lib/baseline.sh
  for s in typecheck lint tests; do install_asset "$r" "$SD/$s.sh" "scripts/sensors/$s.sh"; done
  mkdir -p "$r/.agents/baselines" "$r/pkg" "$r/tests/unit"
  printf '%s\n' "$r"
}
run() { local r="$1" s="$2"; shift 2; out="$(cd "$r" && env STUB_LOG="$r/stub.log" "$@" bash "scripts/sensors/$s.sh" 2>&1)"; rc=$?; }

for s in typecheck lint tests; do
  f="$KEEL/skills/$SD/$s.sh"
  [ -f "$f" ]; check "$s exists" $?
  sed -n 2p "$f" | grep -q '^# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.$'; check "$s managed header" $?
  grep -q '^# --- keel:repo-specific begin ---$' "$f" && grep -q '^# --- keel:repo-specific end ---$' "$f"; check "$s markers" $?
  grep -q "^id=$s\$" "$f"; check "$s id equals file name" $?
done

r="$(mk)"
for s in typecheck lint tests; do
  run "$r" $s; [ $rc -eq 2 ] && printf '%s\n' "$out" | head -1 | grep -q "^$s	.*	skip	.*make bootstrap"; check "$s skips without tool" $?
done

# typecheck
use_stub "$r" mypy .venv/bin/mypy
run "$r" typecheck STUB_OUT="Success: no issues found in 3 source files"
[ $rc -eq 0 ] && [ "$(printf '%s\n' "$out" | head -1)" = "$(printf 'typecheck\tcorrectness\tpass\tSuccess: no issues found in 3 source files')" ]; check "typecheck pass" $?
run "$r" typecheck STUB_EXIT=1 STUB_OUT=$'pkg/a.py:3: error: Incompatible types\npkg/b.py:9: error: Name "x" is not defined\nFound 2 errors in 2 files'
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q '^typecheck	correctness	fail	Found 2 type error' && [ "$(printf '%s\n' "$out" | grep -c '^  pkg/')" -eq 2 ] && printf '%s\n' "$out" | grep -q '^  guidance: '; check "typecheck fail: 2 details + guidance" $?
: > "$r/stub.log"; run "$r" typecheck STUB_OUT="Success: no issues found in 3 source files"; grep -qx '\.' "$r/stub.log"; check "typecheck: mypy gets a target (.) by default" $?
run "$r" typecheck STUB_EXIT=2 STUB_OUT="mypy: error: Missing target module, package, files, or command."
[ $rc -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -q 'mypy exited 2 without reporting a file error' && ! printf '%s\n' "$out" | head -1 | grep -q 'type error'; check "typecheck: a tool error is not reported as a type error" $?

# lint
use_stub "$r" ruff .venv/bin/ruff
echo 1 > "$r/pkg/a.py"; (cd "$r" && git add -A && git commit -q -m a)
JSON="[{\"filename\":\"$r/pkg/a.py\",\"code\":\"E1\"},{\"filename\":\"$r/pkg/a.py\",\"code\":\"E2\"},{\"filename\":\"$r/pkg/a.py\",\"code\":\"E3\"}]"
printf '# measured_at: 2026-10-20 review_by: 2027-04-20\npkg/a.py\t3\n' > "$r/.agents/baselines/lint.tsv"
run "$r" lint STUB_OUT="$JSON"; [ $rc -eq 0 ] && printf '%s\n' "$out" | head -1 | grep -q '^lint	heuristic	pass'; check "lint passes at baseline 3" $?
printf '# h\npkg/a.py\t2\n' > "$r/.agents/baselines/lint.tsv"
run "$r" lint STUB_OUT="$JSON" STUB_EXIT=1; [ $rc -eq 1 ] && printf '%s\n' "$out" | grep -q 'pkg/a.py: 3 problems (allowed 2)' && printf '%s\n' "$out" | grep -q '^  guidance: '; check "lint fails above baseline" $?
: > "$r/stub.log"; run "$r" lint SCOPE=pkg/a.py STUB_OUT="$JSON"; grep -q 'pkg/a.py' "$r/stub.log"; check "lint passes SCOPE files to ruff" $?
run "$r" lint KEEL_MEASURE=1 KEEL_TODAY=2026-10-20 STUB_OUT="$JSON"
[ "$out" = "$(printf '# measured_at: 2026-10-20 review_by: 2027-04-20\npkg/a.py\t3')" ]; check "lint KEEL_MEASURE" $?

# tests
use_stub "$r" pytest .venv/bin/pytest
echo 1 > "$r/pkg/mod.py"; echo 1 > "$r/tests/unit/test_mod.py"; echo 1 > "$r/pkg/orphan.py"
: > "$r/stub.log"; run "$r" tests SCOPE=pkg/mod.py STUB_OUT="3 passed in 0.10s"
[ $rc -eq 0 ] && grep -q 'tests/unit/test_mod.py' "$r/stub.log"; check "tests maps pkg/mod.py to tests/unit/test_mod.py" $?
printf '%s\n' "$out" | head -1 | grep -q '^tests	correctness	pass	3 passed in 0.10s$'; check "tests pass line 1" $?
: > "$r/stub.log"; run "$r" tests SCOPE=pkg/orphan.py; [ $rc -eq 0 ] && [ ! -s "$r/stub.log" ] && printf '%s\n' "$out" | grep -q 'no related test found for the changed files'; check "tests unmapped -> pass without calling pytest" $?
: > "$r/stub.log"; run "$r" tests SCOPE=tests/unit/test_mod.py; grep -q 'tests/unit/test_mod.py' "$r/stub.log"; check "tests: changed test file runs itself" $?
: > "$r/stub.log"; run "$r" tests; [ -s "$r/stub.log" ] && ! grep -q 'test_mod' "$r/stub.log"; check "tests: empty SCOPE -> whole suite" $?
run "$r" tests SCOPE=pkg/mod.py STUB_EXIT=1 STUB_OUT=$'FAILED tests/unit/test_mod.py::test_x - assert 1 == 2\n1 failed, 2 passed in 0.2s'
[ $rc -eq 1 ] && printf '%s\n' "$out" | grep -q '^  FAILED tests/unit/test_mod.py' && printf '%s\n' "$out" | grep -q '^  guidance: .*docs/decisions/'; check "tests fail + guidance" $?
finish
