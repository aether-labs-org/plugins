#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# lint - heuristic. Per-file problem counts compared with .agents/baselines/lint.tsv: fails only
# when a file has more problems than its baseline allows. KEEL_MEASURE=1 prints the baseline rows.
# In:  SCOPE (newline-separated changed files; empty = LINT_PATHS).
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=lint
class=heuristic
# shellcheck disable=SC1091
. scripts/lib/baseline.sh

# --- keel:repo-specific begin ---
ESLINT="node_modules/.bin/eslint"
LINT_PATHS="src"
GUIDANCE='this gate only forbids getting worse. Clear the new problems listed above in the files you just touched; the baselined ones are not yours to fix now. Do not raise .agents/baselines/lint.tsv to make this pass - that single edit is what turns the ratchet off.'
# --- keel:repo-specific end ---

baseline=".agents/baselines/$id.tsv"
if [ ! -x "$ESLINT" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "eslint is not installed - run: make bootstrap"
  exit 2
fi

targets=""
if [ -n "${SCOPE:-}" ] && [ "${KEEL_MEASURE:-}" != 1 ]; then
  targets=$(printf '%s\n' "$SCOPE" | grep -E '\.(ts|tsx|js|jsx)$' | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done)
  if [ -z "$targets" ]; then
    printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "No JS/TS files changed."
    exit 0
  fi
fi

# A temp dir: TMPDIR, else .agents/run/tmp/ (git-ignored), else none.
keel_tmpdir() { mktemp -d 2>/dev/null || { mkdir -p .agents/run/tmp 2>/dev/null && mktemp -d .agents/run/tmp/XXXXXX 2>/dev/null; }; }
tmp="$(keel_tmpdir)" || tmp=""
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no writable temp directory (TMPDIR or .agents/run/tmp/)"
  exit 2
fi
trap 'rm -rf "$tmp"' EXIT
if [ -n "$targets" ]; then
  printf '%s\n' "$targets" | tr '\n' '\0' | xargs -0 "$ESLINT" -f json > "$tmp/eslint.json" 2> "$tmp/eslint.err"
else
  # shellcheck disable=SC2086
  "$ESLINT" -f json $LINT_PATHS > "$tmp/eslint.json" 2> "$tmp/eslint.err"
fi
rc=$?

# JSON -> repo-relative "path<TAB>count" rows
if ! node -e '
  const fs = require("fs"), path = require("path");
  const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const root = process.cwd() + path.sep;
  // A message with no ruleId that is not fatal is ESLint saying the file is ignored, not a problem.
  const rows = data.map(r => [r.filePath.startsWith(root) ? r.filePath.slice(root.length) : r.filePath,
      r.messages.filter(m => m.ruleId || m.fatal).length])
    .filter(r => r[1] > 0).sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
  process.stdout.write(rows.map(r => r[0] + "\t" + r[1]).join("\n") + (rows.length ? "\n" : ""));
' "$tmp/eslint.json" > "$tmp/counts.tsv" 2> /dev/null; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "eslint produced no readable result (exit $rc)."
  { cat "$tmp/eslint.err"; head -c 2000 "$tmp/eslint.json"; } | head -5 | sed 's/^/  /'
  printf '  guidance: %s\n' "Run node_modules/.bin/eslint on the paths above by hand and fix the configuration or parse error it reports."
  exit 1
fi

if [ "${KEEL_MEASURE:-}" = 1 ]; then
  baseline_header
  cat "$tmp/counts.tsv"
  exit 0
fi

now=$(awk -F'\t' '{ s += $2 } END { print s + 0 }' "$tmp/counts.tsv")
based=$(baseline_total "$baseline")
viol="$(baseline_compare "$baseline" "$tmp/counts.tsv")"; brc=$?
if [ "$brc" -eq 2 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "no writable temp directory (TMPDIR or .agents/run/tmp/)"
  exit 2
fi
if [ "$brc" -eq 0 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "$now problems, none above baseline ($based baselined)."
  exit 0
fi
nv=$(printf '%s\n' "$viol" | wc -l | tr -d ' ')
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$nv file(s) above their baseline ($now problems now)."
printf '%s\n' "$viol" | head -5 | awk -F'\t' '{ printf "  %s: %s problems (allowed %s)\n", $1, $2, $3 }'
printf '  guidance: %s\n' "$GUIDANCE"
exit 1
