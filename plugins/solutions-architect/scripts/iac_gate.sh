#!/usr/bin/env bash
# IaC gate: runs every sensor, writes reports/iac-gate.json, prints each sensor's output.
# Usage: iac_gate.sh [IAC_DIR] [MANIFEST] [PLAN_JSON]
# Exit 0 = every sensor passed; 1 = a sensor failed; 2 = incomplete (a mandatory sensor skipped).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export IAC_DIR="${1:-infra}"
export MANIFEST="${2:-architecture/manifest.json}"
plan="${3:-$IAC_DIR/plan.json}"
report_dir="$(dirname "$MANIFEST")/reports"
mkdir -p "$report_dir"
results=()
status=0
run() { # run <command...>
  local out rc line
  out="$("$@" 2>&1)"; rc=$?
  printf '%s\n' "$out" | head -40
  line="$(printf '%s\n' "$out" | head -1)"
  results+=("$line")
  if [ "$rc" -eq 1 ]; then status=1; elif [ "$rc" -eq 2 ] && [ "$status" -eq 0 ]; then status=2; fi
}
run bash "$here/sensors/tf-fmt.sh"
run bash "$here/sensors/tf-validate.sh"
run bash "$here/sensors/tflint.sh"
run bash "$here/sensors/checkov.sh"
if [ -f "$plan" ]; then
  run python3 "$here/sensors/tags.py" "$plan" "$MANIFEST"
else
  results+=("$(printf 'tags\tcorrectness\tskip\tno plan JSON at %s - run terraform plan -lock=false -out=tf.plan and terraform show -json tf.plan' "$plan")")
  printf '%s\n' "${results[${#results[@]}-1]}"
  [ "$status" -eq 0 ] && status=2
fi
printf '%s\n' "${results[@]}" | python3 -c '
import json, sys, datetime
rows = [l.rstrip("\n").split("\t") for l in sys.stdin if l.strip()]
sensors = [{"id": r[0], "class": r[1], "status": r[2], "summary": r[3] if len(r) > 3 else ""} for r in rows]
state = "fail" if any(s["status"] == "fail" for s in sensors) else ("incomplete" if any(s["status"] == "skip" for s in sensors) else "pass")
json.dump({"gate": "iac", "status": state, "at": datetime.date.today().isoformat(), "sensors": sensors},
          open(sys.argv[1], "w"), indent=1)
print(f"iac-gate: {state}")
' "$report_dir/iac-gate.json"
exit $status
