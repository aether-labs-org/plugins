#!/usr/bin/env bash
# gate.sh — runs the fast gate. Invoked by `make gate-fast`.
# Reads the sensor list from .agents/state.yml. No plugin, no network, no model.
set -uo pipefail
cd "$(dirname "$0")/.."
state=".agents/state.yml"
log=".agents/last-run.log"
mkdir -p .agents

# Millisecond clock, portable: `date +%s%N` is GNU-only and silently breaks this
# arithmetic on macOS/BSD `date` (no %N). Bash 5+ gets microsecond precision from
# the builtin $EPOCHREALTIME, no external tool and no GNU dependency; anything
# older (e.g. the bash 3.2 macOS ships by default) falls back to whole seconds via
# $SECONDS, which every bash has had since 2.0. $EPOCHREALTIME's own decimal
# separator follows LC_NUMERIC on at least some bash builds (comma, not period,
# under e.g. a pt_BR locale) - normalise it before splitting, or the arithmetic
# below silently mis-measures instead of erroring.
now_ms() {
  if [ -n "${EPOCHREALTIME:-}" ]; then
    local t="${EPOCHREALTIME/,/.}"
    local sec="${t%.*}" usec="${t#*.}"
    echo $(( sec * 1000 + 10#${usec:0:3} ))
  else
    echo $(( SECONDS * 1000 ))
  fi
}

# Unicode marks only where the terminal can actually render them; plain ASCII
# everywhere else (piped/redirected output, a non-UTF-8 locale, `TERM=dumb`). This
# is the real implementation of the terminal-conditional described below the
# rendered example — not just prose next to a script that always emits one or the
# other. Agents read line 1 and the exit code; these marks are for a human only.
if [ -t 1 ] && locale charmap 2>/dev/null | grep -qi 'utf-8'; then
  m_pass="✓"; m_fail="✗"; m_skip="○"
else
  m_pass="v"; m_fail="x"; m_skip="-"
fi

# SCOPE = files changed since the last commit (tracked + untracked). Empty = whole repo.
SCOPE="$( { git diff --name-only HEAD 2>/dev/null; \
            git ls-files --others --exclude-standard 2>/dev/null; } | sed '/^$/d' | sort -u )"
export SCOPE
n_scope=$(printf '%s' "$SCOPE" | grep -c . )

ceiling=$(sed -n 's/^ *ceiling_seconds: *\([0-9][0-9]*\).*/\1/p' "$state" 2>/dev/null | head -1)
: "${ceiling:=5}"
ids=$(sed -n 's/^ *- id: *\([A-Za-z0-9_-]*\).*/\1/p' "$state" 2>/dev/null)

report=""; total_ms=0; n=0; failed=0; skipped=0
for id in $ids; do
  s="scripts/sensors/$id.sh"
  [ -f "$s" ] || continue
  n=$((n + 1))
  start=$(now_ms)
  out="$(bash "$s" 2>&1)"; rc=$?
  ms=$(( $(now_ms) - start ))
  total_ms=$((total_ms + ms))

  head1=$(printf '%s\n' "$out" | head -1)
  body=$(printf '%s\n' "$out" | tail -n +2)
  cls=$(printf '%s' "$head1" | cut -f2)
  st=$(printf '%s' "$head1" | cut -f3)
  sum=$(printf '%s' "$head1" | cut -f4)

  case "$rc" in
    0) mark="$m_pass" ;;
    2) mark="$m_skip"; skipped=$((skipped + 1)) ;;
    *) mark="$m_fail"; st=fail; failed=$((failed + 1)) ;;
  esac

  if [ "$ms" -ge 1000 ]; then t="$((ms / 1000)).$(( (ms % 1000) / 100 ))s"; else t="${ms}ms"; fi
  report="${report}$(printf '%s %-12s [%-11s] %-44s %8s' "$mark" "$id" "$cls" "$sum" "$t")
"
  [ -n "$body" ] && report="${report}${body}
"
done

if [ "$n_scope" -gt 0 ]; then scope_line="scope: $n_scope files changed since last commit"
else scope_line="scope: whole repository (no uncommitted changes)"; fi
if [ "$total_ms" -ge 1000 ]; then spent="$((total_ms / 1000)).$(( (total_ms % 1000) / 100 ))s"
else spent="${total_ms}ms"; fi
ran=$((n - skipped))
if [ "$skipped" -eq 0 ]; then
  if [ "$failed" -gt 0 ]; then verdict="FAILED ($failed of $n)"; else verdict="PASSED ($n of $n)"; fi
elif [ "$failed" -gt 0 ]; then
  verdict="FAILED ($failed of $ran, $skipped skipped)"
else
  passed=$((ran - failed))
  verdict="PASSED ($passed of $ran, $skipped skipped)"
fi

{
  printf '%s' "$report"
  printf '\n%s\n' "$scope_line"
  printf 'gate: fast - %s | ceiling %ss, spent %s | model cost: US$0.00\n' "$verdict" "$ceiling" "$spent"
} > "$log"

lines=$(wc -l < "$log" | tr -d ' ')
head -40 "$log"
if [ "$lines" -gt 40 ]; then
  printf 'output truncated at 40 lines - full log in .agents/last-run.log\n'
else
  printf 'full log in .agents/last-run.log\n'
fi
[ "$failed" -gt 0 ] && exit 1
exit 0
