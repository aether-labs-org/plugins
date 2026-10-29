#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# pattern - generic rule sensor for a team's own syntactic rule. Counts, per file, the matches of one
# pattern and compares them with .agents/baselines/<id>.tsv (a file may keep the count it had when the
# baseline was written). Installed as scripts/sensors/<rule-id>.sh with id= set to the rule id below.
# Env (.agents/rules/<id>.env): PATTERN (an ERE for grep -E), ENGINE=grep|ast-grep|semgrep (default grep),
# RULE_FILE (ast-grep / semgrep: a committed rule file), INCLUDE and EXCLUDE (git pathspecs, one per
# line), CLASS=heuristic|correctness (default heuristic), MESSAGE (what is wrong), FIX (the right fix).
# ast-grep and semgrep run only when installed; otherwise the sensor skips (exit 2) and says so.
# grep counts matching lines in the C locale, so the result does not depend on the machine's locale.
# In:  SCOPE (newline-separated changed files; empty = all). KEEL_MEASURE=1 prints baseline rows.
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
# --- keel:repo-specific begin ---
# id is the rule's RULE_ID, which is also the file name without .sh; the CLASS key of the env file overrides class.
id=pattern
class=heuristic
# --- keel:repo-specific end ---
# shellcheck disable=SC1090,SC1091
. "${KEEL_BASELINE_LIB:-scripts/lib/baseline.sh}"

RULE_ENV="${RULE_ENV:-.agents/rules/$id.env}"
if [ ! -f "$RULE_ENV" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no .agents/rules/$id.env - run the rules skill"
  exit 2
fi
PATTERN=""; ENGINE=""; RULE_FILE=""; INCLUDE=""; EXCLUDE=""; CLASS=""; MESSAGE=""; FIX=""
# shellcheck disable=SC1090,SC1091
. "${KEEL_ENVPARSE_LIB:-scripts/lib/envparse.sh}" 2>/dev/null || {
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "scripts/lib/envparse.sh is missing - run /keel-harness:build"
  exit 2
}
keel_env_load_sensor "$id" "$class" "$RULE_ENV"
: "${ENGINE:=grep}"

# cfgfail SUMMARY GUIDANCE -> a misconfigured rule is a failure, never a silent pass.
cfgfail() {
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$1"
  printf '  guidance: %s\n' "$2"
  exit 1
}
case "$CLASS" in
  '') ;;
  heuristic | correctness) class="$CLASS" ;;
  *) cfgfail "CLASS=$CLASS in $RULE_ENV is not heuristic or correctness" "Set CLASS=heuristic or CLASS=correctness in $RULE_ENV. A security rule has no baseline and is not a pattern rule." ;;
esac

case "$ENGINE" in
  grep)
    [ -n "$PATTERN" ] || cfgfail "PATTERN is empty in $RULE_ENV" "Set PATTERN to an ERE for grep -E in $RULE_ENV, or set ENGINE and RULE_FILE."
    printf '' | LC_ALL=C grep -E -e "$PATTERN" >/dev/null 2>&1
    [ $? -ne 2 ] || cfgfail "PATTERN in $RULE_ENV is not a valid ERE" "Fix PATTERN in $RULE_ENV so that grep -E accepts it. Do not delete the rule or move the sensor to disabled/ to make this pass." ;;
  ast-grep | semgrep)
    if ! command -v "$ENGINE" >/dev/null 2>&1; then
      printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "$ENGINE is not installed (ENGINE=$ENGINE in $RULE_ENV) - install it, or the rule guards nothing here"
      exit 2
    fi
    [ -n "$RULE_FILE" ] && [ -f "$RULE_FILE" ] || cfgfail "RULE_FILE '$RULE_FILE' for ENGINE=$ENGINE is not a file" "Commit the $ENGINE rule file and name it in RULE_FILE in $RULE_ENV." ;;
  *) cfgfail "ENGINE=$ENGINE in $RULE_ENV is not grep, ast-grep or semgrep" "Set ENGINE=grep, ENGINE=ast-grep or ENGINE=semgrep in $RULE_ENV." ;;
esac

if [ -z "$MESSAGE" ]; then MESSAGE="Remove the matches listed above (rule $id)."; fi
GUIDANCE="$MESSAGE${FIX:+ $FIX} Never add a suppression to make this pass, and do not raise .agents/baselines/$id.tsv or change PATTERN or RULE_FILE in .agents/rules/$id.env."

baseline=".agents/baselines/$id.tsv"
# A temp dir: TMPDIR, else .agents/run/tmp/ (git-ignored), else none.
keel_tmpdir() { mktemp -d 2>/dev/null || { mkdir -p .agents/run/tmp 2>/dev/null && mktemp -d .agents/run/tmp/XXXXXX 2>/dev/null; }; }
tmp="$(keel_tmpdir)" || tmp=""
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no writable temp directory (TMPDIR or .agents/run/tmp/)"
  exit 2
fi
trap 'rm -rf "$tmp"' EXIT

specs=()
while IFS= read -r l; do [ -n "$l" ] && specs[${#specs[@]}]="$l"; done <<LIST
$INCLUDE
LIST
while IFS= read -r l; do [ -n "$l" ] && specs[${#specs[@]}]=":(exclude)$l"; done <<LIST
$EXCLUDE
LIST
git ls-files -z --cached --others --exclude-standard -- ${specs[@]+"${specs[@]}"} | tr '\0' '\n' > "$tmp/cand"

if [ -n "${SCOPE:-}" ] && [ "${KEEL_MEASURE:-}" != 1 ]; then
  printf '%s\n' "$SCOPE" > "$tmp/scope"
  awk 'NR == FNR { s[$0] = 1; next } ($0 in s)' "$tmp/scope" "$tmp/cand" > "$tmp/cand2"
  mv "$tmp/cand2" "$tmp/cand"
fi
checked=0
: > "$tmp/files"
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  checked=$((checked + 1))
  printf '%s\n' "$f" >> "$tmp/files"
done < "$tmp/cand"

# Every engine is reduced to one path per match in $tmp/hits; the counts are made from that.
: > "$tmp/hits"; : > "$tmp/err"
if [ -s "$tmp/files" ]; then
  case "$ENGINE" in
    grep)
      tr '\n' '\0' < "$tmp/files" | LC_ALL=C xargs -0 grep -IcHE -e "$PATTERN" -- 2>/dev/null |
        awk '{ n = match($0, /:[0-9]+$/); if (n > 0) { c = substr($0, n + 1) + 0; for (i = 0; i < c; i++) print substr($0, 1, n - 1) } }' > "$tmp/hits" ;;
    ast-grep)
      tr '\n' '\0' < "$tmp/files" | xargs -0 ast-grep scan --rule "$RULE_FILE" --json=stream -- 2> "$tmp/err" |
        grep -o '"file": *"[^"]*"' | sed 's/^"file": *"//; s/"$//; s|^\./||' > "$tmp/hits" ;;
    semgrep)
      tr '\n' '\0' < "$tmp/files" | xargs -0 env SEMGREP_SEND_METRICS=off SEMGREP_ENABLE_VERSION_CHECK=0 \
        semgrep --config "$RULE_FILE" --json --quiet --metrics=off --disable-version-check -- 2> "$tmp/err" |
        grep -o '"path": *"[^"]*"' | sed 's/^"path": *"//; s/"$//; s|^\./||' > "$tmp/hits" ;;
  esac
  # An engine that printed nothing but an error is a broken rule, not a clean tree.
  if [ "$ENGINE" != grep ] && [ ! -s "$tmp/hits" ] && [ -s "$tmp/err" ]; then
    cfgfail "$ENGINE failed: $(head -1 "$tmp/err" | cut -c1-120)" "Run $ENGINE by hand on RULE_FILE $RULE_FILE and fix the rule file or the install. Do not delete the rule or move the sensor to disabled/ to make this pass."
  fi
fi
LC_ALL=C sort "$tmp/hits" | uniq -c | awk '{ c = $1; sub(/^ *[0-9]+ /, ""); printf "%s\t%d\n", $0, c }' > "$tmp/counts"

if [ "${KEEL_MEASURE:-}" = 1 ]; then
  baseline_header
  cat "$tmp/counts"
  exit 0
fi

over=$(wc -l < "$tmp/counts" | tr -d ' ')
viol="$(baseline_compare "$baseline" "$tmp/counts")"; brc=$?
if [ "$brc" -eq 2 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no writable temp directory (TMPDIR or .agents/run/tmp/)"
  exit 2
fi
if [ "$brc" -eq 0 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "$checked files checked, no new matches ($over files baselined)."
  exit 0
fi
nv=$(printf '%s\n' "$viol" | wc -l | tr -d ' ')
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$nv of $checked files with new matches."
printf '%s\n' "$viol" | head -5 | awk -F'\t' '{ printf "  %s: %s match(es) (allowed %s)\n", $1, $2, $3 }'
printf '  guidance: %s\n' "$GUIDANCE"
exit 1
