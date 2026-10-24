#!/usr/bin/env bash
# Managed by keel-harness. Edit only between the keel:repo-specific markers - see .agents/README.md.
# lint - heuristic. Per-file problem counts from Checkstyle, ktlint or detekt compared with
# .agents/baselines/lint.tsv: fails only when a file has more problems than its baseline allows.
# The linter runs on the whole project; with SCOPE set only the changed files are compared.
# KEEL_MEASURE=1 prints the baseline rows.
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=lint
class=heuristic
# shellcheck disable=SC1091
. scripts/lib/baseline.sh

# --- keel:repo-specific begin ---
LINTER="ktlint"
CMD=(ktlint)
# checkstyle: LINTER="checkstyle" CMD=(./gradlew -q checkstyleMain)
# detekt:     LINTER="detekt"     CMD=(./gradlew -q detekt)
GUIDANCE='this gate only forbids getting worse. Clear the new problems listed above in the files you just touched; the baselined ones are not yours to fix now. Do not raise .agents/baselines/lint.tsv to make this pass - that single edit is what turns the ratchet off.'
# --- keel:repo-specific end ---

baseline=".agents/baselines/$id.tsv"
case "${CMD[0]}" in
  */*) [ -x "${CMD[0]}" ] && have=1 || have=0 ;;
  *) command -v "${CMD[0]}" >/dev/null 2>&1 && have=1 || have=0 ;;
esac
if [ "$have" -ne 1 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "$LINTER is not installed - run: make bootstrap"
  exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
"${CMD[@]}" > "$tmp/lint.out" 2>&1
rc=$?

# path:line(:col)? tokens -> repo-relative path<TAB>count
awk -v root="$PWD/" '
  match($0, /[^[:space:]]+\.(java|kt|kts):[0-9]+/) {
    f = substr($0, RSTART, RLENGTH); sub(/:[0-9]+$/, "", f)
    sub(/^file:\/\//, "", f); if (index(f, root) == 1) f = substr(f, length(root) + 1)
    c[f]++
  }
  END { for (f in c) printf "%s\t%d\n", f, c[f] }' "$tmp/lint.out" | LC_ALL=C sort > "$tmp/counts.tsv"

if [ "$rc" -ne 0 ] && [ ! -s "$tmp/counts.tsv" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$LINTER failed without a parseable report (exit $rc)."
  head -5 "$tmp/lint.out" | sed 's/^/  /'
  printf '  guidance: %s\n' "Run $LINTER by hand and fix the configuration or parse error it reports."
  exit 1
fi

if [ "${KEEL_MEASURE:-}" = 1 ]; then
  baseline_header
  cat "$tmp/counts.tsv"
  exit 0
fi

if [ -n "${SCOPE:-}" ]; then
  printf '%s\n' "$SCOPE" > "$tmp/scope"
  awk -F'\t' 'NR == FNR { s[$0] = 1; next } ($1 in s)' "$tmp/scope" "$tmp/counts.tsv" > "$tmp/scoped.tsv"
  mv "$tmp/scoped.tsv" "$tmp/counts.tsv"
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
