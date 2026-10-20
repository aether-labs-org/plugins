#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
LIB="$KEEL/skills/build/assets/lib/baseline.sh"
[ -f "$LIB" ]; check "baseline.sh exists" $?
# shellcheck disable=SC1090
. "$LIB" 2>/dev/null || true
d="$(mktemp -d)"; _keel_tmps="$_keel_tmps $d"
T="$(printf '\t')"
printf 'a.ts\t2\n' > "$d/c1"
out="$(baseline_compare "$d/none" "$d/c1" 2>/dev/null)"; rc=$?
[ "$out" = "$(printf 'a.ts\t2\t0')" ] && [ $rc -eq 1 ]; check "no baseline: violation allowed 0" $?
printf '# measured_at: 2026-10-20 review_by: 2027-04-20\na.ts\t3\n' > "$d/b1"
printf 'a.ts\t3\n' > "$d/c3"; out="$(baseline_compare "$d/b1" "$d/c3")"; rc=$?
[ -z "$out" ] && [ $rc -eq 0 ]; check "count equal to baseline passes" $?
printf 'a.ts\t2\n' > "$d/c2"; baseline_compare "$d/b1" "$d/c2" >/dev/null; check "shrunk passes" $?
printf 'a.ts\t4\n' > "$d/c4"; out="$(baseline_compare "$d/b1" "$d/c4")"; rc=$?
[ "$out" = "$(printf 'a.ts\t4\t3')" ] && [ $rc -eq 1 ]; check "grown fails with now/allowed" $?
printf 'b.ts\t0\n' > "$d/c0"; baseline_compare "$d/none" "$d/c0" >/dev/null; check "zero count never violates" $?
printf 'src/my file.ts\t3\nsrc/ação.ts\t2\n' > "$d/bs"
printf 'src/my file.ts\t3\nsrc/ação.ts\t2\n' > "$d/cs"
baseline_compare "$d/bs" "$d/cs" >/dev/null; check "paths with spaces and non-ASCII round-trip (equal)" $?
printf 'src/my file.ts\t4\nsrc/ação.ts\t2\n' > "$d/cs2"
out="$(baseline_compare "$d/bs" "$d/cs2")"
[ "$out" = "$(printf 'src/my file.ts\t4\t3')" ]; check "path with space reported intact" $?
printf '# measured_at: x review_by: y\r\na.ts\t3\r\n' > "$d/bcr"; printf 'a.ts\t3\r\n' > "$d/ccr"
baseline_compare "$d/bcr" "$d/ccr" >/dev/null; check "CRLF baseline compares" $?
printf '# h\na\t3\nb\t4\n' > "$d/bt"
[ "$(baseline_total "$d/bt")" = "7" ]; check "baseline_total sums" $?
[ "$(baseline_total "$d/none")" = "0" ]; check "baseline_total missing is 0" $?
[ "$(KEEL_TODAY=2026-10-20 baseline_header)" = "# measured_at: 2026-10-20 review_by: 2027-04-20" ]; check "baseline_header" $?
[ "$(add_months 2026-08-31 6)" = "2027-02-28" ]; check "add_months clamps" $?
[ "$(baseline_review_by "$d/b1")" = "2027-04-20" ]; check "baseline_review_by" $?
[ -z "$(baseline_review_by "$d/none")" ]; check "baseline_review_by missing empty" $?
finish
