#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# diff-coverage - slow-gate correctness sensor. Line coverage of the changed files only, from an
# lcov or JaCoCo XML report; fails when it is under DIFF_COVERAGE_MIN. Never run by the Stop hook.
# Env (.agents/rules/testing-strategy.env): DIFF_COVERAGE_MIN, INCLUDE (optional pathspecs).
# In:  SCOPE (newline-separated changed files). Empty or no covered file changed -> skip.
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=diff-coverage
class=correctness

RULE_ENV="${RULE_ENV:-.agents/rules/testing-strategy.env}"
if [ ! -f "$RULE_ENV" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no .agents/rules/testing-strategy.env - run the rules skill"
  exit 2
fi
DIFF_COVERAGE_MIN=""; INCLUDE=""
eval "$(tr -d '\r' < "$RULE_ENV")"
: "${DIFF_COVERAGE_MIN:=80}"

# --- keel:repo-specific begin ---
FORMAT="lcov"
REPORT="coverage/lcov.info"
CMD=(node_modules/.bin/vitest run --coverage)
# JVM: FORMAT="jacoco" REPORT="build/reports/jacoco/test/jacocoTestReport.xml" CMD=(./gradlew -q test jacocoTestReport)
GUIDANCE="The changed lines listed above are not exercised by any test: add tests for the behaviour you changed (docs/testing.md#testing-strategy). Never lower DIFF_COVERAGE_MIN in .agents/rules/testing-strategy.env to make this pass."
# --- keel:repo-specific end ---

[ -n "${SCOPE:-}" ] || { printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no changed source files"; exit 2; }
case "${CMD[0]}" in
  */*) [ -x "${CMD[0]}" ] && have=1 || have=0 ;;
  *) command -v "${CMD[0]}" >/dev/null 2>&1 && have=1 || have=0 ;;
esac
if [ "$have" -ne 1 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "${CMD[0]} not found - run: make bootstrap"
  exit 2
fi
"${CMD[@]}" >/dev/null 2>&1
if [ ! -f "$REPORT" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no coverage report at $REPORT - the coverage command did not produce one"
  exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
specs=()
while IFS= read -r l; do [ -n "$l" ] && specs[${#specs[@]}]="$l"; done <<LIST
$INCLUDE
LIST
git ls-files -z --cached --others --exclude-standard -- ${specs[@]+"${specs[@]}"} | tr '\0' '\n' > "$tmp/cand"
printf '%s\n' "$SCOPE" > "$tmp/scope"
awk 'NR == FNR { s[$0] = 1; next } ($0 in s)' "$tmp/scope" "$tmp/cand" \
  | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done > "$tmp/changed"
[ -s "$tmp/changed" ] || { printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no changed source files"; exit 2; }

# per executable line in the report: key<TAB>line<TAB>hit (1 covered, 0 not)
if [ "$FORMAT" = jacoco ]; then
  awk 'BEGIN { RS = "<" }
    /^package / { match($0, /name="[^"]*"/); pkg = substr($0, RSTART + 6, RLENGTH - 7) }
    /^sourcefile / { match($0, /name="[^"]*"/); key = pkg "/" substr($0, RSTART + 6, RLENGTH - 7) }
    /^line / { match($0, /nr="[0-9]*"/); nr = substr($0, RSTART + 4, RLENGTH - 5); match($0, /ci="[0-9]*"/)
      printf "%s\t%s\t%d\n", key, nr, (substr($0, RSTART + 4, RLENGTH - 5) + 0 > 0) }
    /^\/sourcefile/ { key = "" }' "$REPORT" > "$tmp/entries"
else
  awk -F'[:,]' '{ sub(/\r$/, "") } /^SF:/ { key = substr($0, 4); next }
    /^DA:/ { printf "%s\t%s\t%d\n", key, $2, ($3 + 0 > 0) }' "$REPORT" > "$tmp/entries"
fi

# changed file -> its key in the report, matched by path suffix
cut -f1 "$tmp/entries" | sort -u > "$tmp/keys"
awk 'NR == FNR { ch[++n] = $0; next }
  { k = $0; for (i = 1; i <= n; i++) { f = ch[i]
      if (f == k || (length(f) > length(k) && substr(f, length(f) - length(k)) == "/" k) || (length(k) > length(f) && substr(k, length(k) - length(f)) == "/" f)) { print f "\t" k; break } } }' \
  "$tmp/changed" "$tmp/keys" > "$tmp/map"
if [ ! -s "$tmp/map" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no changed file appears in the coverage report"
  exit 2
fi

# the changed lines: the + side of `git diff -U0 HEAD` for tracked files, every line of a new file.
# Coverage is measured on these lines only, so touching a legacy file never fails for its old code.
has_head=0; git rev-parse -q --verify HEAD >/dev/null 2>&1 && has_head=1
while IFS= read -r f; do
  if [ "$has_head" = 1 ] && git cat-file -e "HEAD:$f" 2>/dev/null; then
    git diff -U0 HEAD -- "$f" | awk -v f="$f" '/^@@/ { split($3, a, ","); s = substr(a[1], 2) + 0
      c = (a[2] == "" ? 1 : a[2] + 0); for (i = 0; i < c; i++) printf "%s\t%d\n", f, s + i }'
  else
    awk -v f="$f" '{ printf "%s\t%d\n", f, NR }' "$f"
  fi
done < "$tmp/changed" > "$tmp/lines"

# result: "cov tot" on line 1, then file<TAB>uncovered_csv per file with uncovered changed lines
awk -F'\t' 'FILENAME == ARGV[1] { key[$1] = $2; next }
  FILENAME == ARGV[2] { hit[$1 SUBSEP $2] = $3; next }
  { k = key[$1]; if (k == "" || !((k SUBSEP $2) in hit)) next
    tot++; if (hit[k SUBSEP $2] == 1) cov++
    else { if (!($1 in unc)) order[++m] = $1; unc[$1] = unc[$1] (unc[$1] == "" ? "" : ",") $2 } }
  END { print cov + 0, tot + 0; for (i = 1; i <= m; i++) print order[i] "\t" unc[order[i]] }' \
  "$tmp/map" "$tmp/entries" "$tmp/lines" > "$tmp/result"
read -r cov tot < "$tmp/result"
pct=$(awk -v c="$cov" -v t="$tot" 'BEGIN { if (t == 0) print 100; else printf "%d", c * 100 / t }')
if awk -v p="$pct" -v m="$DIFF_COVERAGE_MIN" 'BEGIN { exit !(p + 0 < m + 0) }'; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "diff coverage ${pct}% is below the minimum ${DIFF_COVERAGE_MIN}% ($cov of $tot changed lines)."
  tail -n +2 "$tmp/result" | awk -F'\t' '{ n = split($2, a, ","); s = ""; for (i = 1; i <= n && i <= 5; i++) s = s (i > 1 ? ", " : "") a[i]; printf "  %s: lines %s not covered\n", $1, s }' | head -5
  printf '  guidance: %s\n' "$GUIDANCE"
  exit 1
fi
printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "diff coverage ${pct}% (minimum ${DIFF_COVERAGE_MIN}%, $cov of $tot changed lines)."
exit 0
