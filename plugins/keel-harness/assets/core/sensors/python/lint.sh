#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# lint - heuristic. Per-file problem counts from ruff compared with .agents/baselines/lint.tsv: fails
# only when a file has more problems than its baseline allows. KEEL_MEASURE=1 prints the baseline rows.
# In:  SCOPE (newline-separated changed files; empty = LINT_PATHS).
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=lint
class=heuristic
# shellcheck disable=SC1091
. scripts/lib/baseline.sh

# --- keel:repo-specific begin ---
CMD=(.venv/bin/ruff check --output-format json)
LINT_PATHS="."
GUIDANCE='this gate only forbids getting worse. Clear the new problems listed above in the files you just touched; the baselined ones are not yours to fix now. Do not raise .agents/baselines/lint.tsv to make this pass - that single edit is what turns the ratchet off.'
# --- keel:repo-specific end ---

baseline=".agents/baselines/$id.tsv"
case "${CMD[0]}" in
  */*) [ -x "${CMD[0]}" ] && have=1 || have=0 ;;
  *) command -v "${CMD[0]}" >/dev/null 2>&1 && have=1 || have=0 ;;
esac
if [ "$have" -ne 1 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "ruff is not installed - run: make bootstrap"
  exit 2
fi

targets=""
if [ -n "${SCOPE:-}" ] && [ "${KEEL_MEASURE:-}" != 1 ]; then
  targets=$(printf '%s\n' "$SCOPE" | grep -E '\.pyi?$' | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done)
  if [ -z "$targets" ]; then
    printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "No Python files changed."
    exit 0
  fi
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
if [ -n "$targets" ]; then
  printf '%s\n' "$targets" | tr '\n' '\0' | xargs -0 "${CMD[@]}" > "$tmp/ruff.json" 2> "$tmp/ruff.err"
else
  # shellcheck disable=SC2086
  "${CMD[@]}" $LINT_PATHS > "$tmp/ruff.json" 2> "$tmp/ruff.err"
fi
rc=$?

if ! python3 -c '
import json, os, sys
data = json.load(open(sys.argv[1]))
root = os.getcwd() + os.sep
counts = {}
for d in data:
    f = d.get("filename", "")
    f = f[len(root):] if f.startswith(root) else f
    counts[f] = counts.get(f, 0) + 1
for f in sorted(counts):
    print("%s\t%d" % (f, counts[f]))
' "$tmp/ruff.json" > "$tmp/counts.tsv" 2> /dev/null; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "ruff produced no readable result (exit $rc)."
  { cat "$tmp/ruff.err"; head -c 2000 "$tmp/ruff.json"; } | head -5 | sed 's/^/  /'
  printf '  guidance: %s\n' "Run ruff check on the paths above by hand and fix the configuration or parse error it reports."
  exit 1
fi

if [ "${KEEL_MEASURE:-}" = 1 ]; then
  baseline_header
  cat "$tmp/counts.tsv"
  exit 0
fi

now=$(awk -F'\t' '{ s += $2 } END { print s + 0 }' "$tmp/counts.tsv")
based=$(baseline_total "$baseline")
if viol="$(baseline_compare "$baseline" "$tmp/counts.tsv")"; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "$now problems, none above baseline ($based baselined)."
  exit 0
fi
nv=$(printf '%s\n' "$viol" | wc -l | tr -d ' ')
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$nv file(s) above their baseline ($now problems now)."
printf '%s\n' "$viol" | head -5 | awk -F'\t' '{ printf "  %s: %s problems (allowed %s)\n", $1, $2, $3 }'
printf '  guidance: %s\n' "$GUIDANCE"
exit 1
