#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# code-language - heuristic rule sensor. Counts, per file, the words in identifiers and comments that
# are not in the project's code language: any word with a non-ASCII byte, or a word in the stop-list
# of the language the code must not use (string literals are ignored: user-facing text may be
# anything). Counts are compared with .agents/baselines/code-language.tsv.
# Env (.agents/rules/code-language.env): INCLUDE (git pathspecs, one per line), EXCLUDE (optional),
# STOPLIST (default scripts/sensors/stoplists/pt.txt).
# In:  SCOPE (newline-separated changed files; empty = all). KEEL_MEASURE=1 prints baseline rows;
#      KEEL_MEASURE_WORDS=1 (with KEEL_MEASURE=1) prints files, flagged and the top 10 words.
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=code-language
class=heuristic
# shellcheck disable=SC1090,SC1091
. "${KEEL_BASELINE_LIB:-scripts/lib/baseline.sh}"

RULE_ENV="${RULE_ENV:-.agents/rules/$id.env}"
if [ ! -f "$RULE_ENV" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no .agents/rules/$id.env - run the rules skill"
  exit 2
fi
INCLUDE=""; EXCLUDE=""; STOPLIST=""; ENFORCEMENT_LEVEL=""; EXCEPTIONS=""
# shellcheck disable=SC1090,SC1091
. "${KEEL_ENVPARSE_LIB:-scripts/lib/envparse.sh}" 2>/dev/null || {
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "scripts/lib/envparse.sh is missing - run /keel-harness:build"
  exit 2
}
keel_env_load_sensor "$id" "$class" "$RULE_ENV"
: "${STOPLIST:=scripts/sensors/stoplists/pt.txt}"

# --- keel:repo-specific begin ---
GUIDANCE="Rename the identifiers and rewrite the comments listed above in English (docs/conventions.md#code-language). User-facing text belongs in string literals or i18n files, which this sensor ignores."
# --- keel:repo-specific end ---

if [ ! -f "$STOPLIST" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "stop-list $STOPLIST not found - run the rules skill"
  exit 2
fi

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
# A trailing "/" is dropped: git ignores some :(exclude) pathspecs next to "src/" (2.43), never next to "src".
while IFS= read -r l; do [ -n "$l" ] && { [ "$l" = / ] || l="${l%/}"; specs[${#specs[@]}]="$l"; }; done <<LIST
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
: > "$tmp/files"
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] && grep -Iq . "$f" 2>/dev/null && printf '%s\n' "$f" >> "$tmp/files"
done < "$tmp/cand"
checked=$(wc -l < "$tmp/files" | tr -d ' ')

cat > "$tmp/words.awk" <<'AWK'
function isalpha_(c) { return (c ~ /[A-Za-z]/) || (c !~ /[ -~\t\r\n]/) }
function flush(   lw, flagged) {
  if (word == "") return
  lw = tolower(word)
  flagged = nonascii || (length(lw) >= 2 && (lw in stop))
  if (flagged) print FILENAME "\t" lw
  word = ""; nonascii = 0
}
BEGIN {
  while ((getline w < stoplist) > 0) { gsub(/\r/, "", w); if (w != "" && substr(w, 1, 1) != "#") stop[w] = 1 }
}
{
  line = $0; n = length(line); q = ""; word = ""; nonascii = 0; prevlower = 0
  for (k = 1; k <= n; k++) {
    c = substr(line, k, 1)
    if (q != "") {
      if (c == "\\") k++
      else if (c == q) q = ""
      continue
    }
    if (c == "\"" || c == "'") { flush(); q = c; prevlower = 0; continue }
    if (isalpha_(c)) {
      if (c ~ /[A-Z]/ && prevlower) flush()
      if (c !~ /[A-Za-z]/) nonascii = 1
      word = word c
      prevlower = (c ~ /[a-z]/) || (c !~ /[ -~\t\r\n]/)
    } else { flush(); prevlower = 0 }
  }
  flush()
}
AWK
if [ -s "$tmp/files" ]; then
  tr '\n' '\0' < "$tmp/files" | LC_ALL=C xargs -0 awk -v stoplist="$STOPLIST" -f "$tmp/words.awk" > "$tmp/flagged.tsv"
else
  : > "$tmp/flagged.tsv"
fi
awk -F'\t' '{ c[$1]++ } END { for (p in c) printf "%s\t%d\n", p, c[p] }' "$tmp/flagged.tsv" | LC_ALL=C sort > "$tmp/counts"

if [ "${KEEL_MEASURE:-}" = 1 ]; then
  if [ "${KEEL_MEASURE_WORDS:-}" = 1 ]; then
    printf 'files %s\nflagged %s\n' "$checked" "$(wc -l < "$tmp/flagged.tsv" | tr -d ' ')"
    awk -F'\t' '{ c[$2]++ } END { for (w in c) printf "%s\t%d\n", w, c[w] }' "$tmp/flagged.tsv" | sort -t "$(printf '\t')" -k2,2nr -k1,1 | head -10
  else
    baseline_header
    cat "$tmp/counts"
  fi
  exit 0
fi

# --- mandatory rules (D43): no baseline; EXCEPTIONS are skipped until their deadline, then fail ---
excepted=0
if [ "${ENFORCEMENT_LEVEL:-ratchet}" = mandatory ]; then
  baseline=/dev/null
  mandatory_exceptions "$EXCEPTIONS" "$tmp/counts"
  excepted=$(wc -l < "$tmp/counts.excepted" | tr -d ' ')
fi

over=$(wc -l < "$tmp/counts" | tr -d ' ')
held="$over files baselined"; [ "${ENFORCEMENT_LEVEL:-ratchet}" != mandatory ] || held="$excepted excepted"
viol="$(baseline_compare "$baseline" "$tmp/counts")"; brc=$?
if [ "$brc" -eq 2 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no writable temp directory (TMPDIR or .agents/run/tmp/)"
  exit 2
fi
if [ "$brc" -eq 0 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "$checked files checked, no new non-English words ($held)."
  exit 0
fi
nv=$(printf '%s\n' "$viol" | wc -l | tr -d ' ')
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$nv of $checked files with non-English words."
printf '%s\n' "$viol" | head -5 | awk -F'\t' '{ printf "  %s: %s flagged word(s) (allowed %s)\n", $1, $2, $3 }'
[ -s "$tmp/counts.expired" ] && awk -F'\t' '{ printf "  %s: exception expired on %s\n", $1, $2 }' "$tmp/counts.expired" | head -5
printf '  guidance: %s\n' "$GUIDANCE"
exit 1
