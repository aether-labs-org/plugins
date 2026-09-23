#!/usr/bin/env bash
# checkov - security. Sensor contract: line 1 = id<TAB>class<TAB>status<TAB>summary.
# In: IAC_DIR (default infra), MANIFEST (default architecture/manifest.json).
# Exit 0 pass / 1 fail / 2 skip. Security class: no ratchet, no raisable threshold.
set -uo pipefail
id=checkov
class=security
iac="${IAC_DIR:-infra}"
manifest="${MANIFEST:-architecture/manifest.json}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v checkov >/dev/null 2>&1; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "checkov is not installed - run: uv tool install checkov"
  exit 2
fi

skips=""
if [ -f "$manifest" ]; then
  skips="$(python3 "$here/suppressions.py" "$manifest")"
fi
args=(-d "$iac" --framework terraform --quiet --compact -o json)
[ -n "$skips" ] && args+=(--skip-check "$skips")
out="$(checkov "${args[@]}" 2>/dev/null)"
if ! summary="$(printf '%s' "$out" | python3 "$here/checkov_summary.py")"; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "could not parse checkov JSON output"
  exit 1
fi
n_failed="$(printf '%s\n' "$summary" | head -1 | cut -f1)"
n_passed="$(printf '%s\n' "$summary" | head -1 | cut -f2)"
if [ "$n_failed" -eq 0 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "0 failed checks, $n_passed passed in $iac (suppressed: ${skips:-none})"
  exit 0
fi
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$n_failed failed check(s), $n_passed passed in $iac"
printf '%s\n' "$summary" | tail -n +2 | sed 's/^/  /'
printf '  guidance: fix the resource in %s. Only when an ADR accepts the risk, add\n' "$iac"
printf '  {"check": "<ID>", "resource": "<address>", "justification": "<20+ chars>"} to the manifest\n'
printf '  suppressions. checkov OSS reports no severity, so every unsuppressed failure blocks.\n'
exit 1
