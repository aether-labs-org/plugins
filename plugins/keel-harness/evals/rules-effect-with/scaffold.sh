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

mkdir -p docs
cat > docs/conventions.md <<'MD'
# Conventions

<a id="file-size"></a>
### Source files stay under 300 lines

**Rule.** Source files under `src/` have at most 300 lines.
**Why.** Large files hide several responsibilities and are expensive to read.
**✓ / ✗.** ✓ `posting.ts` (140 lines). ✗ one file with the whole export (600 lines).
**When it fails.** Split the file by responsibility; never raise the limit.

<a id="code-language"></a>
### Identifiers and comments are in English

**Rule.** Identifiers and comments are written in English; string literals may be in any language.
**Why.** Mixed-language names make search unreliable.
**✓ / ✗.** ✓ `totalAmount`. ✗ `valorTotal`.
**When it fails.** Rename the identifiers and rewrite the comments in English.
MD
printf '\n## Rules\n- Source files stay under 300 lines → docs/conventions.md#file-size\n- Identifiers and comments are in English → docs/conventions.md#code-language\n' >> AGENTS.md
git add -A && git -c user.email=eval@local -c user.name=eval commit -qm "rules harness"
