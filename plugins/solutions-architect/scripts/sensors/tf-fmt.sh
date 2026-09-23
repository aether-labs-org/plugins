#!/usr/bin/env bash
# tf-fmt - heuristic-free correctness. Sensor contract line 1: id<TAB>class<TAB>status<TAB>summary.
# In: IAC_DIR (default infra). Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=tf-fmt
class=correctness
iac="${IAC_DIR:-infra}"
if ! command -v terraform >/dev/null 2>&1; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "terraform is not installed - see https://developer.hashicorp.com/terraform/install"
  exit 2
fi
out="$(terraform fmt -check -recursive -list=true "$iac" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "0 files need formatting in $iac"
  exit 0
fi
n=$(printf '%s\n' "$out" | grep -c .)
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$n file(s) need formatting in $iac"
printf '%s\n' "$out" | head -8 | sed 's/^/  /'
printf '  guidance: run terraform fmt -recursive %s; formatting is mechanical, never hand-fix it.\n' "$iac"
exit 1
