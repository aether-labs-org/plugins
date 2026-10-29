#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# journey - slow-gate correctness sensor, opt-in, experimental (D52). Runs the project's Playwright
# journeys (user-visible flows, end to end) and fails when one fails, naming the journey and its trace.
# Playwright has no file-level mode, so SCOPE is not used: every journey under JOURNEY_DIR runs.
# Never run by the Stop hook. Skips when npx or Playwright is not installed.
# Env (.agents/rules/journey.env):
#   JOURNEY_DIR      where the journeys live (default e2e).
#   JOURNEY_RESULTS  where Playwright writes traces (default test-results, its own default).
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=journey
class=correctness

skip() { printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "$1"; exit 2; }

RULE_ENV="${RULE_ENV:-.agents/rules/journey.env}"
[ -f "$RULE_ENV" ] || skip "no .agents/rules/journey.env - the journey sensor is opt-in (see .agents/README.md)"
JOURNEY_DIR=""; JOURNEY_RESULTS=""
# shellcheck disable=SC1090,SC1091
. "${KEEL_ENVPARSE_LIB:-scripts/lib/envparse.sh}" 2>/dev/null || skip "scripts/lib/envparse.sh is missing - run /keel-harness:build"
keel_env_load_sensor "$id" "$class" "$RULE_ENV"
: "${JOURNEY_DIR:=e2e}" "${JOURNEY_RESULTS:=test-results}"

# --- keel:repo-specific begin ---
CMD=(npx playwright test)
PLAYWRIGHT_BIN="node_modules/.bin/playwright"
GUIDANCE="Open the trace of the first failing journey and fix the behaviour it shows. Never edit the journey, loosen its assertions or add a retry to make it pass: a journey describes what a user does, so change it only when that behaviour was changed on purpose, and say so in the pull request."
# --- keel:repo-specific end ---

command -v "${CMD[0]}" >/dev/null 2>&1 || skip "${CMD[0]} not found - install Node.js (make bootstrap)"
[ -e "$PLAYWRIGHT_BIN" ] || skip "Playwright is not installed ($PLAYWRIGHT_BIN missing) - run: make bootstrap, then npx playwright install"
[ -e "$JOURNEY_DIR" ] || skip "journey directory $JOURNEY_DIR does not exist - set JOURNEY_DIR in $RULE_ENV"

out="$("${CMD[@]}" "$JOURNEY_DIR" --reporter=line --trace=retain-on-failure 2>&1)"; rc=$?
# The line reporter writes cursor-control sequences (ESC [ 1 A, ESC [ 2 K) even when it is not a terminal.
esc="$(printf '\033')"
clean="$(printf '%s\n' "$out" | tr -d '\r' | sed "s/${esc}\\[[0-9;]*[A-Za-z]//g")"
if printf '%s\n' "$clean" | grep -qi 'no tests found'; then
  skip "no journeys found under $JOURNEY_DIR"
fi
# The line reporter ends with `  N failed`, `  N passed (2.1s)`, `  N flaky`, `  N skipped`.
count() { printf '%s\n' "$clean" | grep -E "^[[:space:]]*[0-9]+ $1([[:space:]]|\$)" | tail -1 | sed 's/^[[:space:]]*\([0-9]*\).*/\1/'; }
nfailed="$(count failed)"; npassed="$(count passed)"; nflaky="$(count flaky)"
: "${nfailed:=0}" "${npassed:=0}" "${nflaky:=0}"

if [ "$rc" -eq 0 ]; then
  extra=""
  [ "$nflaky" -gt 0 ] && extra=", $nflaky flaky"
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "$npassed journey(s) passed under $JOURNEY_DIR$extra."
  exit 0
fi

# A failing journey is a heading like `  1) checkout.spec.ts:5:1 > checkout completes ----` (the file is relative to
# testDir, a `[project]` precedes it when the config has projects, the arrows are U+203A); its trace is the
# trace.zip Playwright keeps under JOURNEY_RESULTS.
names="$(printf '%s\n' "$clean" | grep -E '^[[:space:]]*[0-9]+\) .*›' | sed 's/^[[:space:]]*[0-9]*) //; s/ ─.*$//')"
traces="$(find "$JOURNEY_RESULTS" -name trace.zip 2>/dev/null | sort | head -2)"
if [ -z "$names" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "playwright failed before reporting a journey result (exit $rc) under $JOURNEY_DIR."
  printf '%s\n' "$clean" | tail -5 | cut -c1-200 | sed 's/^/  /'
  printf '  guidance: %s\n' "Run: ${CMD[*]} $JOURNEY_DIR, and fix what it reports (browsers missing: npx playwright install; a web server that does not start: the webServer entry of playwright.config). The journeys cannot run until it does."
  exit 1
fi
[ "$nfailed" -gt 0 ] || nfailed="$(printf '%s\n' "$names" | grep -c .)"
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$nfailed of $((nfailed + npassed + nflaky)) journey(s) failed under $JOURNEY_DIR."
printf '%s\n' "$names" | head -3 | cut -c1-200 | sed 's/^/  journey: /'
if [ -n "$traces" ]; then
  printf '%s\n' "$traces" | sed 's/^/  trace: /'
  first="$(printf '%s\n' "$traces" | head -1)"
  printf '  guidance: %s Trace viewer: npx playwright show-trace %s\n' "$GUIDANCE" "$first"
else
  printf '  trace: none found under %s (the sensor passes --trace=retain-on-failure)\n' "$JOURNEY_RESULTS"
  printf '  guidance: %s\n' "$GUIDANCE"
fi
exit 1
