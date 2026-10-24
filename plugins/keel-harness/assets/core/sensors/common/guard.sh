#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# guard - security. Fails when the harness itself was loosened since the base commit: a baseline row
# that grew or appeared, a rule limit that relaxed, a widened allow-list, a changed ENFORCEMENT, a
# deleted rule, a fast/slow budget that grew, or a sensor removed or moved to disabled/. A loosening
# passes only when an ADR added in the same change names the loosened file.
# Base: KEEL_GUARD_BASE, else the merge-base with origin/HEAD, else HEAD. SCOPE is not used.
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=guard
class=security

# --- keel:repo-specific begin ---
ADR_DIRS="docs/adr doc/adr docs/decisions docs/architecture/decisions"
GUIDANCE='undo the loosening and fix the code instead. If loosening is really the decision, add an ADR in this same change that names each file listed above and says why. Editing, deleting or disabling this sensor is the wrong fix.'
# --- keel:repo-specific end ---

# shellcheck disable=SC1090,SC1091
. "${KEEL_ENVPARSE_LIB:-scripts/lib/envparse.sh}" 2>/dev/null || {
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "scripts/lib/envparse.sh is missing - run /keel-harness:build"
  exit 2
}
if ! git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "No commits yet - nothing to compare."
  exit 0
fi
base="${KEEL_GUARD_BASE:-}"
if [ -z "$base" ] && git rev-parse --verify -q refs/remotes/origin/HEAD >/dev/null 2>&1; then
  base="$(git merge-base HEAD refs/remotes/origin/HEAD 2>/dev/null)"
fi
: "${base:=HEAD}"
short="$(git rev-parse --short "$base" 2>/dev/null)" || {
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "KEEL_GUARD_BASE=$base is not a commit."
  printf '  guidance: %s\n' "Set KEEL_GUARD_BASE to the branch the change will merge into (e.g. origin/main), or unset it."
  exit 1
}
if ! git cat-file -e "$base:.agents/state.yml" 2>/dev/null; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "Harness installed in this change - nothing to compare (base $short)."
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
: > "$tmp/loose"
loose() { printf '%s\t%s\n' "$1" "$2" >> "$tmp/loose"; } # loose FILE WHAT
at_base() { git show "$base:$1" 2>/dev/null; }           # at_base PATH -> content at base
lines() { printf '%s' "$1" | grep -c '[^[:space:]]'; }
# env_get FILE KEY -> the value, read without executing anything
env_get() { (keel_env_load "$1" >/dev/null 2>&1 || exit 1; eval "printf '%s' \"\${$2-}\""); }
isnum() { case "$1" in '' | *[!0-9]*) return 1 ;; esac; }

# 1. Baselines. TSV: a row whose count grew, or appeared. Other files (native stores): net growth.
{ git ls-tree -r --name-only "$base" -- .agents/baselines/ 2>/dev/null
  git ls-files --cached --others --exclude-standard -- .agents/baselines/ 2>/dev/null; } | sort -u > "$tmp/bfiles"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  at_base "$f" > "$tmp/old"
  if [ -f "$f" ]; then tr -d '\r' < "$f" > "$tmp/new"; else : > "$tmp/new"; fi
  case "$f" in
    *.tsv)
      awk -F'\t' 'FILENAME == ARGV[1] { if ($0 !~ /^#/ && NF >= 2) old[$1] = $2 + 0; next }
        $0 !~ /^#/ && NF >= 2 { o = ($1 in old) ? old[$1] : 0; if ($2 + 0 > o) printf "%s %d -> %d\n", $1, o, $2 }' \
        "$tmp/old" "$tmp/new" | while IFS= read -r w; do loose "$f" "$w"; done ;;
    *)
      o=$(grep -c . "$tmp/old"); n=$(grep -c . "$tmp/new")
      [ "$n" -gt "$o" ] && loose "$f" "native baseline grew from $o to $n lines" ;;
  esac
done < "$tmp/bfiles"

# 2. Rule env files: relaxed limits, widened lists, changed enforcement, deleted rules.
git ls-tree --name-only "$base" -- .agents/rules/ 2>/dev/null | grep '\.env$' > "$tmp/rules"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if [ ! -f "$f" ]; then loose "$f" "rule deleted"; continue; fi
  at_base "$f" > "$tmp/old.env"
  { sed -n 's/^[[:space:]]*\([A-Z_][A-Z0-9_]*\)=.*/\1/p' "$tmp/old.env"; sed -n 's/^[[:space:]]*\([A-Z_][A-Z0-9_]*\)=.*/\1/p' "$f"; } | sort -u > "$tmp/keys"
  while IFS= read -r k; do
    o="$(env_get "$tmp/old.env" "$k")"; n="$(env_get "$f" "$k")"
    [ "$o" = "$n" ] && continue
    case "$k" in
      *MIN*) isnum "$o" && isnum "$n" && [ "$n" -lt "$o" ] && loose "$f" "$k lowered from $o to $n" ;;
      *LIMIT* | *MAX*) isnum "$o" && isnum "$n" && [ "$n" -gt "$o" ] && loose "$f" "$k raised from $o to $n" ;;
      ALLOWED | EXCLUDE | IGNORE_IMPORTS) [ "$(lines "$n")" -gt "$(lines "$o")" ] && loose "$f" "$k widened" ;;
      INCLUDE | FORBIDDEN) [ "$(lines "$n")" -lt "$(lines "$o")" ] && loose "$f" "$k narrowed" ;;
      ENFORCEMENT) loose "$f" "ENFORCEMENT changed from '$o' to '$n'" ;;
    esac
  done < "$tmp/keys"
done < "$tmp/rules"

# 3. Gate budgets.
if [ -f .agents/gate.env ] && at_base .agents/gate.env > "$tmp/old.gate"; then
  for k in CEILING_SECONDS SLOW_CEILING_SECONDS; do
    o="$(env_get "$tmp/old.gate" "$k")"; n="$(env_get .agents/gate.env "$k")"
    isnum "$o" && isnum "$n" && [ "$n" -gt "$o" ] && loose .agents/gate.env "$k raised from $o to $n"
  done
fi

# 4. Sensors removed or moved to disabled/.
git ls-tree --name-only "$base" -- scripts/sensors/ scripts/sensors/slow/ 2>/dev/null | grep '\.sh$' |
  while IFS= read -r f; do
    case "$(basename "$f")" in _*) continue ;; esac
    [ -f "$f" ] || loose "$f" "sensor removed or disabled"
  done

# A loosened file passes when an ADR added since the base names it.
for d in $ADR_DIRS; do
  git diff --name-only --diff-filter=A "$base" -- "$d" 2>/dev/null
  git ls-files --others --exclude-standard -- "$d" 2>/dev/null
done | sort -u > "$tmp/adrs"
: > "$tmp/left"; covered=0
while IFS="$(printf '\t')" read -r f what; do
  [ -n "$f" ] || continue
  ok=0
  while IFS= read -r a; do
    [ -f "$a" ] && grep -qF -- "$f" "$a" && { ok=1; break; }
  done < "$tmp/adrs"
  if [ "$ok" = 1 ]; then covered=$((covered + 1)); else printf '%s: %s\n' "$f" "$what" >> "$tmp/left"; fi
done < "$tmp/loose"

nl=$(grep -c . "$tmp/left")
if [ "$nl" -eq 0 ]; then
  if [ "$covered" -gt 0 ]; then
    printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "$covered loosening(s) since $short, each named by an ADR added in this change."
  else
    printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "No harness file loosened since $short."
  fi
  exit 0
fi
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$nl loosening(s) of the harness since $short without an ADR."
head -5 "$tmp/left" | sed 's/^/  /'
printf '  guidance: %s\n' "$GUIDANCE"
exit 1
