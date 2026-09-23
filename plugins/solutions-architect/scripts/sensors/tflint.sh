#!/usr/bin/env bash
# tflint - correctness. Sensor contract line 1: id<TAB>class<TAB>status<TAB>summary.
# In: IAC_DIR (default infra); the iac skill writes IAC_DIR/.tflint.hcl with the AWS ruleset.
# Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=tflint
class=correctness
iac="${IAC_DIR:-infra}"
if ! command -v tflint >/dev/null 2>&1; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "tflint is not installed - see https://github.com/terraform-linters/tflint#installation"
  exit 2
fi
if ! tflint --chdir="$iac" --init >/dev/null 2>&1; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "tflint --init failed (no network to fetch the AWS ruleset?)"
  exit 2
fi
out="$(tflint --chdir="$iac" --format=compact 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "0 issues in $iac"
  exit 0
fi
n=$(printf '%s\n' "$out" | grep -cE ':[0-9]+:[0-9]+: ')
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$n issue(s) in $iac"
printf '%s\n' "$out" | grep -E ':[0-9]+:[0-9]+: ' | head -8 | sed 's/^/  /'
printf '  guidance: fix each issue at the file:line shown; an invalid instance type or engine version\n'
printf '  means the ADR chose something the region does not offer - revisit the ADR, not just the code.\n'
exit 1
