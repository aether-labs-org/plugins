#!/usr/bin/env bash
# IaC gate: sensor translation and aggregation, with stub tools (plan Task 7).
set -uo pipefail
fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
root="$(cd "$(dirname "$0")/.." && pwd)"
plugin="$root/plugins/solutions-architect"
fx="$root/tests/fixtures/sa/iac"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp -r "$fx/workspace/." "$tmp/"
cd "$tmp"
base_path="/usr/bin:/bin"
gate() { PATH="$1:$base_path" bash "$plugin/scripts/iac_gate.sh" infra architecture/manifest.json infra/plan.json; }
report() { python3 -c 'import json,sys; print(json.load(open("architecture/reports/iac-gate.json"))["status"])'; }

export STUB_CHECKOV_JSON="$fx/checkov-pass.json" STUB_ARGS_FILE="$tmp/checkov-args"
out="$(gate "$fx/stubs")"; rc=$?
[ "$rc" -eq 0 ]; check "all sensors pass -> gate exit 0" $?
[ "$(report)" = "pass" ]; check "report status pass" $?
for s in tf-fmt tf-validate tflint checkov tags; do
  printf '%s\n' "$out" | grep -q "^$s"$'\t'; check "gate ran $s" $?
done
grep -q -- '--skip-check CKV_TF_1' "$tmp/checkov-args"; check "only CKV_TF_1 is skipped globally (D22)" $?

export STUB_CHECKOV_JSON="$fx/checkov-fail.json"
out="$(gate "$fx/stubs")"; rc=$?
[ "$rc" -eq 1 ]; check "a failing security sensor -> gate exit 1" $?
[ "$(report)" = "fail" ]; check "report status fail" $?
printf '%s\n' "$out" | grep -q 'CKV_AWS_16 aws_db_instance.db (main.tf:28)'; check "failure names check, resource and line" $?
printf '%s\n' "$out" | grep -q 'guidance: fix the resource'; check "failure carries guidance" $?

export STUB_CHECKOV_JSON="$fx/checkov-pass.json"
mkdir -p "$tmp/notflint" && ln -sf "$fx/stubs/terraform" "$fx/stubs/checkov" "$tmp/notflint/"
out="$(gate "$tmp/notflint")"; rc=$?
[ "$rc" -eq 2 ]; check "a skipped mandatory sensor -> gate exit 2 (incomplete)" $?
[ "$(report)" = "incomplete" ]; check "report status incomplete" $?

STUB_TF_ERRORS=1 PATH="$fx/stubs:$base_path" IAC_DIR=infra bash "$plugin/scripts/sensors/tf-validate.sh" > "$tmp/v.out"
[ $? -eq 1 ] && grep -q 'main.tf:2 Reference to undeclared input variable' "$tmp/v.out"
check "tf-validate reports file:line" $?

python3 - infra/plan.json <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
del d["resource_changes"][0]["change"]["after"]["tags_all"]["CostCenter"]
json.dump(d, open(p, "w"))
PY
out="$(python3 "$plugin/scripts/sensors/tags.py" infra/plan.json architecture/manifest.json)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q 'aws_s3_bucket.assets: missing CostCenter'
check "tags sensor names the resource and the missing key" $?
exit $fail
