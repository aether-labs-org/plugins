#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# baseline.sh - per-file TSV baseline helpers. Sourced by sensors as: . scripts/lib/baseline.sh
# Baseline format: first line "# measured_at: YYYY-MM-DD review_by: YYYY-MM-DD", then path<TAB>count.
# Sensors never write baselines; KEEL_MEASURE=1 prints what keel should write.

# add_months DATE N -> YYYY-MM-DD, day clamped to the target month's last day.
add_months() {
  awk -v d="$1" -v n="$2" 'BEGIN {
    split(d, p, "-"); y = p[1] + 0; m = p[2] + 0; day = p[3] + 0
    t = (y * 12 + (m - 1)) + n; y = int(t / 12); m = t % 12 + 1
    split("31 28 31 30 31 30 31 31 30 31 30 31", ml, " ")
    last = ml[m]
    if (m == 2 && ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0)) last = 29
    if (day > last) day = last
    printf "%04d-%02d-%02d\n", y, m, day
  }'
}

# baseline_header -> "# measured_at: <today> review_by: <today + 6 months>"
baseline_header() {
  local today
  today="${KEEL_TODAY:-$(date +%Y-%m-%d)}"
  printf '# measured_at: %s review_by: %s\n' "$today" "$(add_months "$today" 6)"
}

# A temp file: TMPDIR, else .agents/run/tmp/ (git-ignored), else none.
keel_tmpfile() { mktemp 2>/dev/null || { mkdir -p .agents/run/tmp 2>/dev/null && mktemp .agents/run/tmp/XXXXXX 2>/dev/null; }; }

# baseline_compare BASELINE_FILE COUNTS_FILE
# Prints path<TAB>now<TAB>allowed per violation; returns 0 when none, 1 otherwise,
# 2 when no temp file can be made (the calling sensor reports skip).
baseline_compare() {
  local base="$1" counts="$2" out empty=""
  if [ ! -s "$base" ]; then
    empty="$(keel_tmpfile)" || empty=""
    if [ -z "$empty" ] || [ ! -f "$empty" ]; then return 2; fi
    echo "# none" > "$empty"; base="$empty"
  fi
  out="$(awk -F'\t' '
    { sub(/\r$/, "") }
    NR == FNR { if ($0 !~ /^#/ && NF >= 2) allowed[$1] = $2 + 0; next }
    $0 ~ /^#/ || NF < 2 { next }
    { now = $2 + 0; a = ($1 in allowed) ? allowed[$1] : 0
      if (now > 0 && now > a) printf "%s\t%d\t%d\n", $1, now, a }
  ' "$base" "$counts")"
  [ -z "$empty" ] || rm -f "$empty"
  if [ -n "$out" ]; then printf '%s\n' "$out"; return 1; fi
  return 0
}

# baseline_total BASELINE_FILE -> sum of counts (0 when missing)
baseline_total() {
  if [ ! -f "$1" ]; then echo 0; return 0; fi
  awk -F'\t' '{ sub(/\r$/, "") } $0 !~ /^#/ && NF >= 2 { s += $2 } END { print s + 0 }' "$1"
}

# baseline_review_by BASELINE_FILE -> review_by value (empty when missing)
baseline_review_by() {
  [ -f "$1" ] || return 0
  sed -n '1s/\r$//;1s/.*review_by: *\([0-9-]*\).*/\1/p' "$1"
}
