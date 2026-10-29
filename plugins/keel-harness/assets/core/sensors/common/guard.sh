#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# guard - security. Fails when the harness itself was loosened since the base commit: a baseline row
# that grew or appeared, a rule limit that relaxed, a widened allow-list, a changed ENFORCEMENT, a
# deleted rule, a fast/slow budget that grew, or a sensor removed or moved to disabled/. A loosening
# passes only when an ADR added in the same change names the loosened file. For a rule with
# ENFORCEMENT_LEVEL=mandatory (D43) that is not enough: any loosening of its env file, sensors or
# baselines, a later EXCEPTIONS deadline or a new exception line, or a lower ENFORCEMENT_LEVEL needs a
# superseding ADR (a `Supersedes: <existing ADR path>` line) that names the file.
# Base: KEEL_GUARD_BASE, else the merge-base with origin/HEAD, else HEAD. SCOPE is not used.
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=guard
class=security

# --- keel:repo-specific begin ---
ADR_DIRS="docs/adr doc/adr docs/decisions docs/architecture/decisions"
GUIDANCE='undo the loosening and fix the code instead. If loosening is really the decision, add an ADR in this same change that names each file listed above and says why. Editing, deleting or disabling this sensor is the wrong fix.'
GUIDANCE_MANDATORY='a line marked [mandatory] belongs to a rule with ENFORCEMENT_LEVEL=mandatory: an ADR that only names the file does not unlock it. Undo the loosening, or add a superseding ADR in this same change that names the file, says why, and has a line "Supersedes: <path of an existing ADR>" pointing at an existing ADR in the ADR folder. CODEOWNERS plus branch protection must approve it; keel cannot check that locally.'
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

# The ADR folder the rules skill recorded wins over the default list.
adr_dir="$(sed -n 's/^adr_dir:[[:space:]]*\([^#[:space:]]*\).*/\1/p' .agents/state.yml 2>/dev/null | head -1)"
[ -n "$adr_dir" ] && ADR_DIRS="$adr_dir"

# A temp dir: TMPDIR, else .agents/run/tmp/ (git-ignored), else none.
keel_tmpdir() { mktemp -d 2>/dev/null || { mkdir -p .agents/run/tmp 2>/dev/null && mktemp -d .agents/run/tmp/XXXXXX 2>/dev/null; }; }
tmp="$(keel_tmpdir)" || tmp=""
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "no writable temp directory (TMPDIR or .agents/run/tmp/)"
  printf '  guidance: %s\n' "make TMPDIR writable or let the gate create .agents/run/tmp/; never delete this sensor"
  exit 1
fi
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

# 5. Mandatory rules (D43). A rule with ENFORCEMENT_LEVEL=mandatory (at the base) is not loosened by an
# ordinary ADR: its env file, its sensors and its baselines are "hard" files (hardmap: path<TAB>rule env),
# and a loosening of one needs a superseding ADR (below). Extra loosenings checked here: the level going
# down or disappearing, an EXCEPTIONS line added, a deadline moved later. A baseline for a mandatory rule
# that is not at the base is already caught by section 1 (its rows appear) and is hard here.
: > "$tmp/hardmap"
hard_add() { printf '%s\t%s\n' "$1" "$2" >> "$tmp/hardmap"; } # hard_add PATH RULE_ENV
# exc_rows VALUE -> path<TAB>date for each valid EXCEPTIONS line (the date is the last word of the line)
exc_rows() {
  printf '%s\n' "$1" | tr -d '\r' | awk '{ sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }
    /^#/ || $0 == "" { next }
    match($0, /[ \t]+[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) { d = substr($0, RSTART); sub(/^[ \t]+/, "", d); p = substr($0, 1, RSTART - 1); if (p != "") print p "\t" d }'
}
# mand_sensors ENVFILE RULE_ENV -> the rule's sensors and baselines are hard files
mand_sensors() {
  local it s
  for it in $(env_get "$1" ENFORCEMENT | tr ',' ' '); do
    case "$it" in
      sensor:?*) s="${it#sensor:}"; hard_add ".agents/baselines/$s.tsv" "$2"; hard_add "scripts/sensors/$s.sh" "$2"; hard_add "scripts/sensors/slow/$s.sh" "$2" ;;
    esac
  done
}
{ git ls-tree --name-only "$base" -- .agents/rules/ 2>/dev/null | grep '\.env$'
  git ls-files --cached --others --exclude-standard -- '.agents/rules/*.env' 2>/dev/null; } | sort -u > "$tmp/allrules"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  lo=""; ln=""; had=0
  if git cat-file -e "$base:$f" 2>/dev/null; then
    had=1; at_base "$f" > "$tmp/m.old"; lo="$(env_get "$tmp/m.old" ENFORCEMENT_LEVEL)"
  fi
  [ -f "$f" ] && ln="$(env_get "$f" ENFORCEMENT_LEVEL)"
  [ "$ln" = mandatory ] && mand_sensors "$f" "$f"
  [ "$had" = 1 ] && [ "$lo" = mandatory ] || continue
  hard_add "$f" "$f"; mand_sensors "$tmp/m.old" "$f"
  [ -f "$f" ] || continue # a deleted rule is reported by section 2
  if ! grep -q '^[[:space:]]*ENFORCEMENT_LEVEL=' "$f"; then
    loose "$f" "ENFORCEMENT_LEVEL removed (was mandatory)"
  elif [ "$ln" != mandatory ]; then
    loose "$f" "ENFORCEMENT_LEVEL changed from mandatory to ${ln:-empty}"
  fi
  exc_rows "$(env_get "$tmp/m.old" EXCEPTIONS)" > "$tmp/e.old"
  exc_rows "$(env_get "$f" EXCEPTIONS)" > "$tmp/e.new"
  awk -F'\t' 'NR == FNR { if (!($1 in o) || $2 < o[$1]) o[$1] = $2; next }
    !($1 in o) { printf "EXCEPTIONS gained %s (due %s)\n", $1, $2; next }
    $2 > o[$1] { printf "EXCEPTIONS deadline for %s moved later (%s -> %s)\n", $1, o[$1], $2 }' "$tmp/e.old" "$tmp/e.new" |
    while IFS= read -r w; do loose "$f" "$w"; done
done < "$tmp/allrules"
is_hard() { awk -F'\t' -v p="$1" '$1 == p { found = 1 } END { exit !found }' "$tmp/hardmap"; }

# A loosened file passes when an ADR added since the base names it. A hard file needs a superseding ADR:
# one that names the file (or the mandatory rule it belongs to) and has a line `Supersedes: <path>`
# pointing at an existing ADR (at the base) in an ADR folder.
for d in $ADR_DIRS; do
  git diff --name-only --diff-filter=A "$base" -- "$d" 2>/dev/null
  git ls-files --others --exclude-standard -- "$d" 2>/dev/null
done | sort -u > "$tmp/adrs"
: > "$tmp/sadrs"
while IFS= read -r a; do
  [ -f "$a" ] || continue
  sed -n 's/^[[:space:]]*Supersedes:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$a" | while IFS= read -r t; do
    t="${t#./}"
    for d in $ADR_DIRS; do
      case "$t" in "$d"/*) git cat-file -e "$base:$t" 2>/dev/null && { printf '%s\n' "$a" >> "$tmp/sadrs"; break; } ;; esac
    done
  done
done < "$tmp/adrs"
: > "$tmp/left"; covered=0; nhard=0
while IFS="$(printf '\t')" read -r f what; do
  [ -n "$f" ] || continue
  ok=0
  if is_hard "$f"; then
    awk -F'\t' -v p="$f" '$1 == p { print $2 }' "$tmp/hardmap" | sort -u > "$tmp/names"
    while IFS= read -r a; do
      [ -f "$a" ] || continue
      if grep -qF -- "$f" "$a"; then ok=1; break; fi
      while IFS= read -r nm; do grep -qF -- "$nm" "$a" && { ok=1; break; }; done < "$tmp/names"
      [ "$ok" = 1 ] && break
    done < "$tmp/sadrs"
    if [ "$ok" != 1 ]; then nhard=$((nhard + 1)); what="$what [mandatory]"; fi
  else
    while IFS= read -r a; do
      [ -f "$a" ] && grep -qF -- "$f" "$a" && { ok=1; break; }
    done < "$tmp/adrs"
  fi
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
if [ "$nhard" -gt 0 ]; then
  printf '  guidance: %s %s\n' "$GUIDANCE" "$GUIDANCE_MANDATORY"
else
  printf '  guidance: %s\n' "$GUIDANCE"
fi
exit 1
