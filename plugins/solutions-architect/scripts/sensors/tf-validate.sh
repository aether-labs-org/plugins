#!/usr/bin/env bash
# tf-validate - correctness. Sensor contract line 1: id<TAB>class<TAB>status<TAB>summary.
# In: IAC_DIR (default infra). Needs providers: runs terraform init -backend=false first.
# Exit 0 pass / 1 fail / 2 skip.
set -uo pipefail
id=tf-validate
class=correctness
iac="${IAC_DIR:-infra}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v terraform >/dev/null 2>&1; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "terraform is not installed - see https://developer.hashicorp.com/terraform/install"
  exit 2
fi
if ! terraform -chdir="$iac" init -backend=false -input=false >/dev/null 2>&1; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" skip "terraform init -backend=false failed (no network or registry access?)"
  exit 2
fi
out="$(terraform -chdir="$iac" validate -json 2>/dev/null)"
if ! res="$(printf '%s' "$out" | python3 "$here/validate_summary.py" 2>/dev/null)"; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "could not parse terraform validate -json"
  exit 1
fi
errors="$(printf '%s\n' "$res" | head -1 | cut -f1)"
warnings="$(printf '%s\n' "$res" | head -1 | cut -f2)"
if [ "$errors" -eq 0 ]; then
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" pass "0 errors, $warnings warning(s) in $iac"
  exit 0
fi
printf '%s\t%s\t%s\t%s\n' "$id" "$class" fail "$errors error(s), $warnings warning(s) in $iac"
printf '%s\n' "$res" | tail -n +2 | sed 's/^/  /'
printf '  guidance: fix the first error; later ones are often its cascade.\n'
exit 1
