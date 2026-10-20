#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# architecture-grep - correctness rule sensor, the fast fallback for architecture.sh. It reads the
# same map (.agents/rules/architecture.env: LAYERS, FORBIDDEN) and counts, per file, the imports
# that cross a layer boundary not listed in allowed_csv plus the imports of FORBIDDEN prefixes.
# Counts are compared with .agents/baselines/architecture-grep.tsv. Java, Kotlin and Python only.
# In:  SCOPE (newline-separated changed files; empty = all). KEEL_MEASURE=1 prints baseline rows.
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=architecture-grep
class=correctness
# shellcheck disable=SC1090,SC1091
. "${KEEL_BASELINE_LIB:-scripts/lib/baseline.sh}"

RULE_ENV="${RULE_ENV:-.agents/rules/architecture.env}"
if [ ! -f "$RULE_ENV" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no .agents/rules/architecture.env - run the rules skill"
  exit 2
fi
LAYERS=""; FORBIDDEN=""
orig_lang="${LANG-}"
eval "$(tr -d '\r' < "$RULE_ENV")"
arch_lang="${LANG-}"
LANG="$orig_lang"

# --- keel:repo-specific begin ---
GUIDANCE="Move the dependency behind a port owned by the inner layer, or move the code to the layer allowed to depend on it (docs/architecture.md#architecture). Do not edit .agents/rules/architecture.env or raise .agents/baselines/architecture-grep.tsv to make this pass."
# --- keel:repo-specific end ---

case "$arch_lang" in
  java) glob='*.java' ;;
  kotlin) glob='*.kt' ;;
  python) glob='*.py' ;;
  ts)
    printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "use architecture.sh with ENGINE=depcruise for TypeScript"
    exit 2 ;;
  *)
    printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "unsupported LANG '$arch_lang' in architecture.env"
    exit 2 ;;
esac

baseline=".agents/baselines/$id.tsv"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

{
  printf '%s\n' "$LAYERS" | sed '/^$/d' | tr '|' '\t' | sed 's/^/L\t/'
  printf '%s\n' "$FORBIDDEN" | sed '/^$/d' | tr '|' '\t' | sed 's/^/F\t/'
} > "$tmp/spec"

git ls-files -z --cached --others --exclude-standard -- "$glob" | tr '\0' '\n' > "$tmp/cand"
if [ -n "${SCOPE:-}" ] && [ "${KEEL_MEASURE:-}" != 1 ]; then
  printf '%s\n' "$SCOPE" > "$tmp/scope"
  awk 'NR == FNR { s[$0] = 1; next } ($0 in s)' "$tmp/scope" "$tmp/cand" > "$tmp/cand2"
  mv "$tmp/cand2" "$tmp/cand"
fi
while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done < "$tmp/cand" > "$tmp/files"
checked=$(wc -l < "$tmp/files" | tr -d ' ')

cat > "$tmp/count.awk" <<'AWK'
function under(t, p,   lp) {
  lp = length(p)
  if (p == "" || index(t, p) != 1) return 0
  return (substr(p, lp, 1) == "." || length(t) == lp || substr(t, lp + 1, 1) == ".")
}
BEGIN {
  FS_ = "\t"
  while ((getline line < spec) > 0) {
    n = split(line, a, "\t")
    if (a[1] == "L") { nl++; lname[nl] = a[2]; lpath[nl] = a[3]; limp[nl] = a[4]; lallow[nl] = "," a[5] "," }
    else if (a[1] == "F") { nf++; flayer[nf] = a[2]; fpre[nf] = a[3] }
  }
}
FNR == 1 {
  if (cur != "") print cur "\t" cnt
  cur = FILENAME; cnt = 0; mine = 0; best = -1
  for (i = 1; i <= nl; i++) if (index(FILENAME, lpath[i] "/") == 1 && length(lpath[i]) > best) { mine = i; best = length(lpath[i]) }
}
mine == 0 { next }
{
  t = ""
  if (lang == "python") { if (match($0, /^[ \t]*(from|import)[ \t]+/)) { t = substr($0, RLENGTH + 1); sub(/[ \t\r].*$/, "", t) } }
  else if (match($0, /^[ \t]*import[ \t]+(static[ \t]+)?/)) { t = substr($0, RLENGTH + 1); sub(/[; \t\r].*$/, "", t) }
  if (t == "") next
  for (i = 1; i <= nl; i++) {
    if (i == mine) continue
    if (under(t, limp[i]) && index(lallow[mine], "," lname[i] ",") == 0) { cnt++; break }
  }
  for (i = 1; i <= nf; i++) if (flayer[i] == lname[mine] && under(t, fpre[i])) cnt++
}
END { if (cur != "") print cur "\t" cnt }
AWK
if [ -s "$tmp/files" ]; then
  tr '\n' '\0' < "$tmp/files" | xargs -0 awk -v lang="$arch_lang" -v spec="$tmp/spec" -f "$tmp/count.awk" > "$tmp/counts.raw"
else
  : > "$tmp/counts.raw"
fi
# the awk emits the previous file when a new one starts; drop rows with no layer (they print nothing)
awk -F'\t' 'NF >= 2' "$tmp/counts.raw" > "$tmp/counts"

if [ "${KEEL_MEASURE:-}" = 1 ]; then
  baseline_header
  awk -F'\t' '$2 > 0' "$tmp/counts" | LC_ALL=C sort
  exit 0
fi

total=$(awk -F'\t' '{ s += $2 } END { print s + 0 }' "$tmp/counts")
based=$(baseline_total "$baseline")
if viol="$(baseline_compare "$baseline" "$tmp/counts")"; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "$checked files checked, no new architecture violations ($based baselined)."
  exit 0
fi
nv=$(printf '%s\n' "$viol" | wc -l | tr -d ' ')
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$nv file(s) with new architecture violations ($total in all)."
printf '%s\n' "$viol" | head -5 | awk -F'\t' '{ printf "  %s: %s architecture violation(s) (allowed %s)\n", $1, $2, $3 }'
printf '  guidance: %s\n' "$GUIDANCE"
exit 1
