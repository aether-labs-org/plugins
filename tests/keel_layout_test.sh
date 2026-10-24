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
finish
