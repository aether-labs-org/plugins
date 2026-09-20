#!/usr/bin/env bash
set -uo pipefail
fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
root="$(cd "$(dirname "$0")/.." && pwd)"
sk="$root/plugins/keel-harness/skills/build"

[ -f "$sk/references/agents-md-template.md" ]; check "agents-md-template.md exists" $?
! grep -q "120" "$sk/references/agents-md-template.md" 2>/dev/null; check "template ceiling is not 120" $?
grep -q "100" "$sk/references/agents-md-template.md" 2>/dev/null; check "template ceiling is 100" $?
[ -f "$sk/references/context-engineering.md" ]; check "context-engineering.md copied" $?

grep -q "model_baseline" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md writes model_baseline" $?
grep -q "installed_at" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md writes installed_at" $?
grep -q "not_installed" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md records declined layers" $?
grep -qi "before writing anything" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md states the confirmation gate" $?
grep -qi "never invent" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md keeps the never-invent-commands rule" $?
grep -q "100 lines" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md enforces the 100-line ceiling" $?
grep -qi "resumable" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md is resumable layer by layer" $?

# Portuguese state keys are a regression: the spec fixed English keys.
! grep -qE "instalado_em|camadas|nao_instaladas|classe:|revisar_em" "$sk/SKILL.md" 2>/dev/null
check "state keys are English" $?

[ -f "$sk/references/sensor-contract.md" ]; check "sensor-contract.md exists" $?
for field in "pass signal" "guidance" "scope" "class" "cost" "ceiling" "verbosity"; do
  grep -qi "$field" "$sk/references/sensor-contract.md" 2>/dev/null
  check "contract field: $field" $?
done
for cls in security correctness heuristic; do
  grep -q "$cls" "$sk/references/sensor-contract.md" 2>/dev/null; check "contract class: $cls" $?
done
grep -qi "never" "$sk/references/sensor-contract.md" 2>/dev/null; check "contract forbids ratcheting security" $?
grep -q "review_by" "$sk/references/sensor-contract.md" 2>/dev/null; check "heuristic snapshots expire" $?

[ -f "$sk/references/sensors-by-language.md" ]; check "sensors-by-language.md exists" $?
grep -q "GitLeaks" "$sk/references/sensors-by-language.md" 2>/dev/null; check "secret scanner named" $?
grep -qi "names tools, never commands" "$sk/references/sensors-by-language.md" 2>/dev/null
check "language table states the tools-not-commands rule" $?

grep -q "PostToolUse" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md writes the PostToolUse hook" $?
! grep -q "PreToolUse" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md installs no blocking hook" $?
grep -q "gate-fast" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md writes the gate-fast target" $?
grep -q "ceiling_seconds" "$sk/SKILL.md" 2>/dev/null; check "SKILL.md honours the gate ceiling" $?

exit $fail
