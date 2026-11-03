#!/usr/bin/env bash
# F5 Task 2 (C8, experimental per D52): the opt-in journey sensor and the structured-log guidance.
# Stubs only: npx is a stub on PATH, no browser, no network.
# shellcheck disable=SC2319 # `check "..." $?` right after a [ ] test is this suite's idiom
set -uo pipefail
qgrep() { grep "$@" >/dev/null; } # reads all its input: `| grep -q` can SIGPIPE the writer under pipefail
. "$(dirname "$0")/keel_helpers.sh"
TAB="$(printf '\t')"
W="$(mktemp -d)"; _keel_tmps="$_keel_tmps $W"
line1() { printf '%s\n' "$1" | head -1; }
detail() { printf '%s\n' "$1" | tail -n +2 | grep -c '^  [^ ]'; } # lines after line 1 that are indented two spaces
JY="$KEEL/assets/core/sensors/slow/journey.sh"

[ -f "$JY" ]; check "journey.sh exists under assets/core/sensors/slow/" $?
f="$JY"
head -2 "$f" | qgrep '^# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.$'; check "journey.sh: managed header" $?
[ "$(grep -c 'keel:repo-specific begin' "$f")" = 1 ] && [ "$(grep -c 'keel:repo-specific end' "$f")" = 1 ]; check "journey.sh: one repo-specific block" $?
grep 'experimental' "$f" >/dev/null; check "journey.sh: marked experimental (D52)" $?

# ------------------------------------------------------------------ journey
# mkjy -> a repo with the sensor, the libs, a journey.env, Playwright 'installed' and a stub npx on PATH
mkjy() {
  local r; r="$(new_repo)"
  install_asset "$r" assets/core/lib/envparse.sh scripts/lib/envparse.sh
  install_asset "$r" assets/core/sensors/slow/journey.sh scripts/sensors/slow/journey.sh
  use_stub "$r" _template bin/npx
  mkdir -p "$r/.agents/rules" "$r/e2e" "$r/node_modules/.bin"
  : > "$r/node_modules/.bin/playwright"
  printf 'JOURNEY_DIR=e2e\n' > "$r/.agents/rules/journey.env"
  echo 'test("x", async () => {});' > "$r/e2e/checkout.spec.ts"
  printf '.agents/run/\nnode_modules/\ntest-results/\n' > "$r/.gitignore"
  printf '%s\n' "$r"
}
# jy REPO [ENV...] -> out, rc (npx is the stub in REPO/bin)
jy() { local r="$1"; shift; out="$(cd "$r" && env PATH="$r/bin:$PATH" STUB_LOG="$r/npx.log" "$@" bash scripts/sensors/slow/journey.sh 2>"$W/jy.err")"; rc=$?; }
jy_skip() { [ "$rc" -eq 2 ] && line1 "$out" | qgrep "^journey${TAB}correctness${TAB}skip${TAB}"; }

FAILED_OUT='
Running 7 tests using 1 worker
[1/7] [chromium] › e2e/cart.spec.ts:4:1 › add to cart
  1) [chromium] › e2e/checkout.spec.ts:5:1 › checkout completes ──────────────────────────────────

    Error: expect(locator).toHaveText(expected)

    Expected string: "1"
    Received string: "2"

  2) [chromium] › e2e/search.spec.ts:3:1 › search finds an item ─────────────────────────────────

    Error: expect(locator).toBeVisible()

  2 failed
    [chromium] › e2e/checkout.spec.ts:5:1 › checkout completes ───────────────────────────────────
    [chromium] › e2e/search.spec.ts:3:1 › search finds an item ───────────────────────────────────
  5 passed (3.4s)
'

r="$(mkjy)"; rm "$r/.agents/rules/journey.env"
jy "$r"; jy_skip && line1 "$out" | qgrep 'opt-in'; check "journey: no journey.env -> skip (opt-in)" $?
r="$(mkjy)"; rm "$r/node_modules/.bin/playwright"
jy "$r"; jy_skip && line1 "$out" | qgrep 'Playwright is not installed' && [ ! -e "$r/npx.log" ]; check "journey: Playwright not installed -> skip, and npx is not run" $?
r="$(mkjy)"; sed -i.bak 's|^CMD=.*|CMD=(keel-no-such-npx playwright test)|' "$r/scripts/sensors/slow/journey.sh"
jy "$r"; jy_skip && line1 "$out" | qgrep 'keel-no-such-npx not found'; check "journey: no npx -> skip" $?
r="$(mkjy)"; rm -rf "$r/e2e"
jy "$r"; jy_skip && line1 "$out" | qgrep 'journey directory e2e does not exist'; check "journey: JOURNEY_DIR missing -> skip" $?
r="$(mkjy)"
jy "$r" STUB_EXIT=1 STUB_OUT='Error: No tests found.'; jy_skip && line1 "$out" | qgrep 'no journeys found under e2e'; check "journey: playwright finds no tests -> skip" $?
r="$(mkjy)"; rm "$r/scripts/lib/envparse.sh"
jy "$r"; jy_skip && line1 "$out" | qgrep 'envparse.sh is missing'; check "journey: no envparse.sh -> skip" $?

r="$(mkjy)"
jy "$r" STUB_EXIT=0 STUB_OUT='Running 5 tests using 1 worker
  5 passed (3.2s)'
[ "$rc" -eq 0 ] && line1 "$out" | qgrep -E "^journey${TAB}correctness${TAB}pass${TAB}5 journey\(s\) passed under e2e\.\$"; check "journey: all pass -> pass with the count" $?
qgrep -x 'playwright test e2e --reporter=line --trace=retain-on-failure' "$r/npx.log"; check "journey: runs npx playwright test <JOURNEY_DIR> with the line reporter and traces on failure" $?
[ "$(detail "$out")" -eq 0 ]; check "journey: a pass prints no detail lines" $?
jy "$r" STUB_EXIT=0 STUB_OUT='  1 flaky
  4 passed (3.2s)'
[ "$rc" -eq 0 ] && line1 "$out" | qgrep -E '4 journey\(s\) passed under e2e, 1 flaky'; check "journey: flaky journeys are named in a pass" $?
printf 'JOURNEY_DIR=tests/journeys\n' > "$r/.agents/rules/journey.env"; mkdir -p "$r/tests/journeys"
jy "$r" STUB_EXIT=0 STUB_OUT='  1 passed'; qgrep -x 'playwright test tests/journeys --reporter=line --trace=retain-on-failure' "$r/npx.log"; check "journey: JOURNEY_DIR from the env file is the argument" $?

r="$(mkjy)"; mkdir -p "$r/test-results/checkout-completes-chromium" "$r/test-results/search-finds-an-item-chromium"
: > "$r/test-results/checkout-completes-chromium/trace.zip"; : > "$r/test-results/search-finds-an-item-chromium/trace.zip"
jy "$r" STUB_EXIT=1 STUB_OUT="$FAILED_OUT"
[ "$rc" -eq 1 ] && line1 "$out" | qgrep -E "^journey${TAB}correctness${TAB}fail${TAB}2 of 7 journey\(s\) failed under e2e\.\$"; check "journey: failures -> fail, line 1 in the contract (2 of 7)" $?
printf '%s\n' "$out" | qgrep -F '  journey: [chromium] › e2e/checkout.spec.ts:5:1 › checkout completes'; check "journey: names the failing journey" $?
printf '%s\n' "$out" | qgrep -F '  journey: [chromium] › e2e/search.spec.ts:3:1 › search finds an item'; check "journey: names every failing journey (up to 3)" $?
! printf '%s\n' "$out" | qgrep '──'; check "journey: the heading rule line is cut from the journey name" $?
printf '%s\n' "$out" | qgrep -F '  trace: test-results/checkout-completes-chromium/trace.zip'; check "journey: gives the trace path" $?
printf '%s\n' "$out" | qgrep -F 'npx playwright show-trace test-results/checkout-completes-chromium/trace.zip'; check "journey: guidance gives the trace viewer command for the first trace" $?
printf '%s\n' "$out" | qgrep '^  guidance: .*Never edit the journey'; check "journey: guidance names the wrong fix" $?
[ "$(printf '%s\n' "$out" | tail -n +2 | grep -c '^  [a-z]*:')" -le 6 ]; check "journey: at most 5 detail lines and the guidance" $?
! printf '%s\n' "$out" | qgrep 'Expected string'; check "journey: the assertion text is not dumped" $?
r="$(mkjy)"
jy "$r" STUB_EXIT=1 STUB_OUT="$FAILED_OUT"
[ "$rc" -eq 1 ] && printf '%s\n' "$out" | qgrep -F '  trace: none found under test-results'; check "journey: no trace on disk is said, not invented" $?
r="$(mkjy)"; printf 'JOURNEY_DIR=e2e\nJOURNEY_RESULTS=out/pw\n' > "$r/.agents/rules/journey.env"; mkdir -p "$r/out/pw/x"; : > "$r/out/pw/x/trace.zip"
jy "$r" STUB_EXIT=1 STUB_OUT="$FAILED_OUT"; printf '%s\n' "$out" | qgrep -F '  trace: out/pw/x/trace.zip'; check "journey: JOURNEY_RESULTS moves the trace search" $?
r="$(mkjy)"
jy "$r" STUB_EXIT=1 STUB_OUT='Error: Cannot find module "@playwright/test"'
[ "$rc" -eq 1 ] && line1 "$out" | qgrep -E "${TAB}fail${TAB}playwright failed before reporting a journey result \(exit 1\)" && printf '%s\n' "$out" | qgrep -F 'Cannot find module'; check "journey: a crash before any result is a fail with the last lines, never a pass" $?
jy "$r" STUB_EXIT=1 STUB_OUT=''; [ "$rc" -eq 1 ]; check "journey: a non-zero exit with no output is a fail" $?

# The line reporter's real output, captured from Playwright 1.48.2 (tests/fixtures/keel/playwright/): it writes
# cursor-control sequences even when piped, the heading has no [project] and the file is relative to testDir.
PWF="$FIXTURES/playwright"
r="$(mkjy)"; mkdir -p "$r/test-results/cart-add-to-cart-updates-the-count"; : > "$r/test-results/cart-add-to-cart-updates-the-count/trace.zip"
jy "$r" STUB_EXIT=1 STUB_OUT="$(cat "$PWF/line-reporter-failed.txt")"
[ "$rc" -eq 1 ] && line1 "$out" | qgrep -E "^journey${TAB}correctness${TAB}fail${TAB}1 of 1 journey\(s\) failed under e2e\.\$"; check "journey (real output): a failed run -> fail, 1 of 1" $?
printf '%s\n' "$out" | qgrep -F '  journey: cart.spec.js:2:1 › add to cart updates the count'; check "journey (real output): names the journey, without the ANSI codes or the rule line" $?
printf '%s\n' "$out" | qgrep -F '  trace: test-results/cart-add-to-cart-updates-the-count/trace.zip'; check "journey (real output): finds the trace" $?
! printf '%s\n' "$out" | qgrep "$(printf '\033')"; check "journey (real output): no escape character reaches the gate" $?
r="$(mkjy)"
jy "$r" STUB_EXIT=0 STUB_OUT="$(cat "$PWF/line-reporter-passed.txt")"
[ "$rc" -eq 0 ] && line1 "$out" | qgrep -E "${TAB}pass${TAB}2 journey\(s\) passed under e2e\.\$"; check "journey (real output): a passed run -> pass, 2 journeys" $?
jy "$r" STUB_EXIT=0 STUB_OUT="$(cat "$PWF/line-reporter-flaky.txt")"
[ "$rc" -eq 0 ] && line1 "$out" | qgrep -E "${TAB}pass${TAB}2 journey\(s\) passed under e2e, 1 flaky\.\$"; check "journey (real output): a flaky run that passed -> pass, flaky named" $?
jy "$r" STUB_EXIT=1 STUB_OUT="$(cat "$PWF/line-reporter-none.txt")"
jy_skip && line1 "$out" | qgrep 'no journeys found under e2e'; check "journey (real output): 'No tests found' -> skip" $?
[ ! -s "$W/jy.err" ]; check "journey: nothing on stderr" $?


! grep -n 'mktemp' "$JY" | qgrep .; check "journey.sh makes no temp file" $?
grep -E 'claude|REVIEWER|curl|wget' "$JY" >/dev/null; [ $? -ne 0 ]; check "journey.sh calls no model and no network tool" $?

# ------------------------------------------------------------------ docs
PL="$KEEL/contracts/profile-l.md"
qgrep 'journey.sh' "$PL" && qgrep 'JOURNEY_DIR' "$PL" && qgrep 'JOURNEY_RESULTS' "$PL" && qgrep 'show-trace' "$PL"; check "contracts/profile-l.md documents journey.env" $?
qgrep 'slow/journey.sh' "$KEEL/contracts/sensor.md"; check "contracts/sensor.md lists journey.sh among the assets" $?
CE="$KEEL/skills/build/references/context-engineering.md"
qgrep -i 'structured log' "$CE" && qgrep '"level"' "$CE" && qgrep '"msg"' "$CE" && qgrep 'grep' "$CE"; check "context-engineering.md: structured-log guidance with a JSON line shape agents can grep" $?
sed -n '/Structured logs/,/^### Reading/p' "$CE" | qgrep -i 'trace_id'; check "context-engineering.md: names a correlation id" $?
sed -n '/Structured logs/,/^### Reading/p' "$CE" | qgrep -i 'why'; check "context-engineering.md: says why" $?
sed -n '/Structured logs/,/^### Reading/p' "$CE" | qgrep -iE 'journey|playwright'; check "context-engineering.md: ties the log line to the journey sensor" $?
for s in build rules; do
  qgrep -i 'journey' "$KEEL/skills/$s/SKILL.md" && qgrep -i 'experimental' "$KEEL/skills/$s/SKILL.md"; check "$s SKILL.md mentions the journey sensor as optional and experimental" $?
done
qgrep 'journey' "$KEEL/assets/core/README.agents.md" && qgrep 'JOURNEY_DIR' "$KEEL/assets/core/README.agents.md"; check "README.agents.md explains how to add the journey sensor" $?
finish
