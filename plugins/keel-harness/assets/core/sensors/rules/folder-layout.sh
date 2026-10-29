#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# folder-layout - correctness rule sensor. A file under INCLUDE must match one ALLOWED pattern
# (shell case patterns, one per line; * crosses /). Files adopted before the rule can be baselined
# in .agents/baselines/folder-layout.tsv (count 1 per misplaced file).
# Env (.agents/rules/folder-layout.env): INCLUDE (git pathspecs), EXCLUDE (optional), ALLOWED.
# In:  SCOPE (newline-separated changed files; empty = all files). KEEL_MEASURE=1 prints baseline rows.
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=folder-layout
class=correctness
# shellcheck disable=SC1090,SC1091
. "${KEEL_BASELINE_LIB:-scripts/lib/baseline.sh}"

RULE_ENV="${RULE_ENV:-.agents/rules/$id.env}"
if [ ! -f "$RULE_ENV" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no .agents/rules/$id.env - run the rules skill"
  exit 2
fi
INCLUDE=""; EXCLUDE=""; ALLOWED=""; ENFORCEMENT_LEVEL=""; EXCEPTIONS=""
# shellcheck disable=SC1090,SC1091
. "${KEEL_ENVPARSE_LIB:-scripts/lib/envparse.sh}" 2>/dev/null || {
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "scripts/lib/envparse.sh is missing - run /keel-harness:build"
  exit 2
}
keel_env_load_sensor "$id" "$class" "$RULE_ENV"

# --- keel:repo-specific begin ---
GUIDANCE="Move each file above to where docs/architecture.md#folder-layout says it belongs. Never widen ALLOWED in .agents/rules/folder-layout.env or raise .agents/baselines/folder-layout.tsv to make this pass."
# --- keel:repo-specific end ---

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

printf '%s\n' "$ALLOWED" | sed '/^$/d' > "$tmp/patterns"
checked=0
: > "$tmp/counts"
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  checked=$((checked + 1))
  ok=0
  while IFS= read -r pat; do
    # shellcheck disable=SC2254
    case "$f" in $pat) ok=1; break ;; esac
  done < "$tmp/patterns"
  if [ "$ok" -eq 1 ]; then printf '%s\t0\n' "$f" >> "$tmp/counts"; else printf '%s\t1\n' "$f" >> "$tmp/counts"; fi
done < "$tmp/cand"

if [ "${KEEL_MEASURE:-}" = 1 ]; then
  baseline_header
  awk -F'\t' '$2 > 0' "$tmp/counts" | LC_ALL=C sort
  exit 0
fi

# --- mandatory rules (D43): no baseline; EXCEPTIONS are skipped until their deadline, then fail ---
excepted=0
if [ "${ENFORCEMENT_LEVEL:-ratchet}" = mandatory ]; then
  baseline=/dev/null
  mandatory_exceptions "$EXCEPTIONS" "$tmp/counts"
  excepted=$(wc -l < "$tmp/counts.excepted" | tr -d ' ')
fi

over=$(awk -F'\t' '$2 > 0' "$tmp/counts" | wc -l | tr -d ' ')
held="$over baselined"; [ "${ENFORCEMENT_LEVEL:-ratchet}" != mandatory ] || held="$excepted excepted"
viol="$(baseline_compare "$baseline" "$tmp/counts")"; brc=$?
if [ "$brc" -eq 2 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no writable temp directory (TMPDIR or .agents/run/tmp/)"
  exit 2
fi
if [ "$brc" -eq 0 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "$checked files checked, all in an allowed location ($held)."
  exit 0
fi
nv=$(printf '%s\n' "$viol" | wc -l | tr -d ' ')
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$nv of $checked files outside the allowed layout."
printf '%s\n' "$viol" | head -5 | awk -F'\t' '{ printf "  %s: not in an allowed location\n", $1 }'
[ -s "$tmp/counts.expired" ] && awk -F'\t' '{ printf "  %s: exception expired on %s\n", $1, $2 }' "$tmp/counts.expired" | head -5
printf '  guidance: %s\n' "$GUIDANCE"
exit 1
