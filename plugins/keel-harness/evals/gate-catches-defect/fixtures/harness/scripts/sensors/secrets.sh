#!/usr/bin/env bash
# secrets — security. Wrapper protocol: see the kit's sensor contract.
# In:  SCOPE (unused - GitLeaks has no per-file batch mode, so this sensor is whole-repo by
#      nature, the same way typecheck.sh is for tsc).
# Out: line 1 = id<TAB>class<TAB>status<TAB>summary. Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=secrets
class=security

gitleaks_bin="$(command -v gitleaks || true)"
if [ -z "$gitleaks_bin" ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "gitleaks is not installed - install it and re-run make gate-fast"
  exit 2
fi

tmp_report="$(mktemp)"
trap 'rm -f "$tmp_report"' EXIT
"$gitleaks_bin" detect --no-git --source . --report-format json --report-path "$tmp_report" >/dev/null 2>&1
rc=$?

if [ "$rc" -eq 0 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "No leaks found in the repository."
  exit 0
fi

leaks=$(grep -c '"RuleID"' "$tmp_report" 2>/dev/null); : "${leaks:=1}"
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$leaks leaked credential(s) found in the repository."
grep -oE '"File":"[^"]*"' "$tmp_report" 2>/dev/null | sed 's/"File":"//;s/"$//' | sort -u | head -5 | sed 's/^/  /'
printf '  guidance: rotate every credential in the files listed above right now, then remove it\n'
printf '  from source and load it from an environment variable or secret manager at runtime -\n'
printf '  deleting it from the latest commit is not enough, it is still readable from git history.\n'
printf '  GitLeaks only matches contiguous patterns: a literal built from string concatenation\n'
printf '  (like "sk_live_" + "...") will not trip this sensor, so treat any provider-prefix-plus-\n'
printf '  suffix construction as a leak even when this sensor stays green.\n'
exit 1
