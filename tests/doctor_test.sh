#!/usr/bin/env bash
set -uo pipefail
fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
root="$(cd "$(dirname "$0")/.." && pwd)"
f="$root/plugins/keel-harness/skills/doctor/SKILL.md"
has() { grep -qF -- "$1" "$f" 2>/dev/null; }

has "100 lines"; check "AGENTS.md size is covered" $?
! has "model_baseline"; check "no model_baseline check (replaced by review-due)" $?
has 'harness-check.sh'; check "runs harness-check.sh" $?
has '${CLAUDE_PLUGIN_ROOT}/assets/core/harness-check.sh'; check "runs the plugin's copy of the validator" $?
has 'prompt-audit'; check "points at /doctor prompt-audit" $?
grep -qi "writes nothing" "$f"; check "doctor writes nothing" $?
grep -qi "exactly one warning" "$f"; check "one condition produces one warning" $?
has 'cmp'; check "proposes updating scripts/harness-check.sh when it differs (cmp)" $?
for id in agents-size stale-command agents-not-loaded dangling-pointer hook-missing run-state guard-missing sensor-malformed sensor-unavailable \
          rule-inconsistent topic-size baseline-malformed baseline-stale review-due; do
  has "$id"; check "check id: $id" $?
done
! grep -qi "capture rate" "$f"; check "no history-dependent checks" $?
ev="$root/plugins/keel-harness/evals/doctor-validator-drift"
for x in case.yaml prompt.md scaffold.sh; do [ -f "$ev/$x" ]; check "doctor-validator-drift has $x" $?; done
[ "$(ls "$ev/graders" 2>/dev/null | wc -l)" -ge 3 ]; check "doctor-validator-drift has graders" $?
bash -n "$ev/scaffold.sh" 2>/dev/null; check "doctor-validator-drift scaffold parses" $?
[ ! -e "$root/plugins/keel-harness/evals/doctor-agents-not-loaded" ]; check "doctor-agents-not-loaded retired (E1)" $?
for c in doctor-finds-drift doctor-validator-drift; do grep -q "allowed_tools: \[.*Bash" "$root/plugins/keel-harness/evals/$c/prompt.md"; check "$c grants Bash (doctor runs the validator)" $?; done
! grep -rq 'sensors:' "$root/plugins/keel-harness/evals/gate-catches-defect/fixtures/harness/.agents/state.yml"; check "eval fixture state has no sensors list" $?
exit $fail
