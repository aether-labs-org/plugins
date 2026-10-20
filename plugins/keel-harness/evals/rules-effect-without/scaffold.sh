#!/usr/bin/env bash
# Same repository and harness in both arms: the build-typescript repo, the bundled build assets, and
# the file-size and code-language rule sensors with their env files and no .claude/settings.json.
# Only the -with arm also has the rule lines in AGENTS.md and the anchored sections in docs/.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$here/../build-typescript/scaffold.sh"
# shellcheck disable=SC1091
. "$here/../rules-brownfield/harness.sh"
install_harness --typescript
install_rule_sensors file-size code-language
printf "RULE_ID=file-size\nKIND=metric\nORIGIN=proposed\nAPPROVED_AT=2026-10-20\nENFORCEMENT=sensor:file-size\nDOC=docs/conventions.md#file-size\nLIMIT=300\nINCLUDE='src'\n" > .agents/rules/file-size.env
printf "RULE_ID=code-language\nKIND=convention\nORIGIN=proposed\nAPPROVED_AT=2026-10-20\nENFORCEMENT=sensor:code-language\nDOC=docs/conventions.md#code-language\nINCLUDE='src'\nSTOPLIST='scripts/sensors/stoplists/pt.txt'\n" > .agents/rules/code-language.env
rm -rf .claude
git add -A && git -c user.email=eval@local -c user.name=eval commit -qm "rules harness"
