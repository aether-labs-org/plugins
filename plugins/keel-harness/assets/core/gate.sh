#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# gate.sh - runs the fast or the slow gate: `bash scripts/gate.sh [fast|slow]` (default fast).
# Fast runs scripts/sensors/*.sh, slow runs scripts/sensors/slow/*.sh (sorted by name; files whose
# name starts with `_` and subdirectories are ignored). Budgets come from .agents/gate.env.
# No plugin, no network, no model.
set -uo pipefail
mode="${1:-fast}"
case "$mode" in fast | slow) ;; *) echo "usage: gate.sh [fast|slow]" >&2; exit 64 ;; esac
cd "$(dirname "$0")/.." || exit 1
mkdir -p .agents/run
if [ "$mode" = slow ]; then
  dir="scripts/sensors/slow"; log=".agents/run/last-run-slow.log"; key=SLOW_CEILING_SECONDS; default=600
else
  dir="scripts/sensors"; log=".agents/run/last-run.log"; key=CEILING_SECONDS; default=30
fi

# Millisecond clock, portable: `date +%s%N` is GNU-only. Bash 5+ has $EPOCHREALTIME (its decimal
# separator may be a comma under some locales - normalised); older bash falls back to $SECONDS.
now_ms() {
  if [ -n "${EPOCHREALTIME:-}" ]; then
    local t="${EPOCHREALTIME/,/.}"
    local sec="${t%.*}" usec="${t#*.}"
    echo $((sec * 1000 + 10#${usec:0:3}))
  else
    echo $((SECONDS * 1000))
  fi
}

# Marks for humans only; agents read line 1 and the exit code.
if [ -t 1 ] && locale charmap 2>/dev/null | grep -qi 'utf-8'; then
  m_pass="✓"; m_fail="✗"; m_skip="○"
else
  m_pass="v"; m_fail="x"; m_skip="-"
fi

# Budget from .agents/gate.env (never sourced; CRLF tolerated).
ceiling=""
if [ -f .agents/gate.env ]; then
  ceiling="$(tr -d '\r' < .agents/gate.env | sed -n "s/^$key=\\([0-9][0-9]*\\).*/\\1/p" | head -1)"
fi
: "${ceiling:=$default}"

# SCOPE = files changed since the last commit (tracked, not deleted, plus untracked), minus
# keel's own run state (.agents/run/, and v0.2's .agents/last-* and .agents/.gate-lock/) in case
# .gitignore misses it.
# Empty means the whole repository, which is also the case before the first commit.
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  SCOPE="$({ git -c core.quotepath=off diff --name-only --diff-filter=d HEAD 2>/dev/null
    git -c core.quotepath=off ls-files --others --exclude-standard 2>/dev/null; } | sed '/^$/d' |
    grep -vE '^\.agents/(run/.*|last-[^/]*|\.gate-lock/.*)$' | sort -u)"
  empty_scope_note="no uncommitted changes"
else
  SCOPE=""
  empty_scope_note="no commits yet"
fi
export SCOPE
n_scope=$(printf '%s' "$SCOPE" | grep -c .)

report=""; total_ms=0; n=0; failed=0; skipped=0
for s in "$dir"/*.sh; do
  [ -f "$s" ] || continue
  id="$(basename "$s" .sh)"
  case "$id" in _*) continue ;; esac
  n=$((n + 1))
  start=$(now_ms)
  out="$(bash "$s" 2>&1)"; rc=$?
  ms=$(($(now_ms) - start))
  total_ms=$((total_ms + ms))

  head1=$(printf '%s\n' "$out" | head -1)
  body=$(printf '%s\n' "$out" | tail -n +2)
  cls=$(printf '%s' "$head1" | cut -f2)
  sum=$(printf '%s' "$head1" | cut -f4)

  case "$rc" in
    0) mark="$m_pass" ;;
    2) mark="$m_skip"; skipped=$((skipped + 1)) ;;
    *) mark="$m_fail"; failed=$((failed + 1)) ;;
  esac

  if [ "$ms" -ge 1000 ]; then t="$((ms / 1000)).$(((ms % 1000) / 100))s"; else t="${ms}ms"; fi
  report="${report}$(printf '%s %-12s [%-11s] %-44s %8s' "$mark" "$id" "$cls" "$sum" "$t")
"
  [ -n "$body" ] && report="${report}${body}
"
done

if [ "$n_scope" -gt 0 ]; then scope_line="scope: $n_scope files changed since last commit"
else scope_line="scope: whole repository ($empty_scope_note)"; fi
if [ "$total_ms" -ge 1000 ]; then spent="$((total_ms / 1000)).$(((total_ms % 1000) / 100))s"
else spent="${total_ms}ms"; fi
over=""
[ "$total_ms" -gt $((ceiling * 1000)) ] && over=" (over ceiling)"
ran=$((n - skipped))
if [ "$skipped" -eq 0 ]; then
  if [ "$failed" -gt 0 ]; then verdict="FAILED ($failed of $n)"; else verdict="PASSED ($n of $n)"; fi
elif [ "$failed" -gt 0 ]; then
  verdict="FAILED ($failed of $ran, $skipped skipped)"
else
  verdict="PASSED ($((ran - failed)) of $ran, $skipped skipped)"
fi

{
  printf '%s' "$report"
  printf '\n%s\n' "$scope_line"
  printf 'gate: %s - %s | ceiling %ss, spent %s%s | model cost: US$0.00\n' "$mode" "$verdict" "$ceiling" "$spent" "$over"
} > "$log"

lines=$(wc -l < "$log" | tr -d ' ')
head -40 "$log"
if [ "$lines" -gt 40 ]; then
  printf 'output truncated at 40 lines - full log in %s\n' "$log"
else
  printf 'full log in %s\n' "$log"
fi
[ "$failed" -gt 0 ] && exit 1
exit 0
