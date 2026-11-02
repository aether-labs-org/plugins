#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
# The v0.3 plugin layout (spec §4): what is copied into a repository lives in assets/, what runs from
# the plugin lives in scripts/, and skills reach both through ${CLAUDE_PLUGIN_ROOT}.
for d in skills/build/assets skills/rules/assets; do
  [ ! -e "$KEEL/$d" ]; check "no $d (moved to assets/ and scripts/)" $?
done
for f in assets/core/gate.sh assets/core/gate.env assets/core/harness-check.sh assets/core/README.agents.md \
         assets/core/lib/baseline.sh assets/core/lib/envparse.sh assets/core/lib/junit.sh \
         assets/core/sensors/common/guard.sh assets/core/sensors/common/secrets.sh \
         assets/core/sensors/typescript/lint.sh assets/core/sensors/python/lint.sh assets/core/sensors/jvm/lint.sh \
         assets/core/sensors/rules/file-size.sh assets/core/sensors/rules/slow/mutation.sh \
         assets/core/sensors/rules/stoplists/pt.txt \
         assets/adapters/claude/claude-stop.sh assets/adapters/claude/settings-stop.json \
         assets/adapters/claude/claude-protect.sh assets/adapters/claude/settings-protect.json assets/core/consequence.yml \
         scripts/measure.sh scripts/render.sh; do
  [ -f "$KEEL/$f" ]; check "$f exists" $?
done
[ ! -e "$KEEL/bin" ]; check "no bin/ (claude.ai and Cowork do not install a plugin that has one)" $?
! grep -rn 'CLAUDE_SKILL_DIR}/\.\./' "$KEEL/skills" >/dev/null; check "no skill reaches into a sibling skill" $?
! grep -rn 'CLAUDE_SKILL_DIR}/assets' "$KEEL/skills" >/dev/null; check "skills reach bundled files through \${CLAUDE_PLUGIN_ROOT}" $?
missing="$(grep -rhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./-]+' "$KEEL/skills" | sed 's#^\${CLAUDE_PLUGIN_ROOT}/##; s#[.,]*$##' | sort -u |
  while IFS= read -r p; do [ -e "$KEEL/$p" ] || printf '%s\n' "$p"; done)"
[ -z "$missing" ]; check "every \${CLAUDE_PLUGIN_ROOT}/ path a skill cites exists${missing:+ (missing: $missing)}" $?
! grep -n 'assets/core/sensors/rules' "$KEEL/skills/build/SKILL.md" "$KEEL/skills/build/references/sensors-by-language.md" >/dev/null
check "build cites the stack sensors (assets/core/sensors/), not the rule sensors" $?
grep -q 'PLUGIN_ROOT}/assets/core/sensors/rules/' "$KEEL/skills/rules/SKILL.md"; check "rules copies its sensors from assets/core/sensors/rules/" $?
! grep -rnE 'skills/(build|rules)/assets' "$KEEL" "$(dirname "$0")"/*.sh --exclude=keel_layout_test.sh >/dev/null; check "no reference to the old asset paths in the plugin or the tests" $?

# F2c-1: contracts/ is the single source every skill points at (spec section 4)
for f in sensor rule-env plan state flow consequence; do
  [ -f "$KEEL/contracts/$f.md" ]; check "contracts/$f.md exists" $?
done
for d in skills/build/references/sensor-contract.md skills/rules/references/rule-env.md skills/rules/references/plan-template.md; do
  [ ! -e "$KEEL/$d" ]; check "$d moved to contracts/" $?
done
! grep -rnE '\.\./(build|rules|assess)/' "$KEEL/skills" >/dev/null; check "no SKILL.md or reference reaches into a sibling skill (../build/, ../rules/, ../assess/)" $?
! grep -rnE '(^|[^/])(references/(sensor-contract|rule-env|plan-template)\.md)' "$KEEL/skills" "$KEEL/contracts" >/dev/null; check "no skill cites a contract at its old references/ path" $?
grep -q '## Phases' "$KEEL/contracts/flow.md" && grep -q '## Traceability' "$KEEL/contracts/flow.md"; check "contracts/flow.md has Phases and Traceability headings" $?
for k in schema_version installed_at harness_review_by mode adr_dir layers not_installed bootstrap guides fast_gate slow_gate hook ci precommit rules; do
  grep -q "\`$k\`" "$KEEL/contracts/state.md" 2>/dev/null; check "contracts/state.md documents $k" $?
done
finish
