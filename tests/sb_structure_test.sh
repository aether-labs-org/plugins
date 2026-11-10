#!/usr/bin/env bash
# Structural checks for the second-brain plugin (spec sections 3, 6, 10).
# `claude plugin validate --strict` (AC8) runs in `make validate`: the CI installs claude after this suite.
set -uo pipefail
fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
root="$(cd "$(dirname "$0")/.." && pwd)"
p="$root/plugins/second-brain"
mp="$root/.claude-plugin/marketplace.json"
pj="$p/.claude-plugin/plugin.json"

jq -e '.plugins[] | select(.name == "second-brain" and .source == "./plugins/second-brain")' "$mp" >/dev/null
check "marketplace lists second-brain" $?
jq -e '.plugins[] | select(.name == "second-brain") | has("version") | not' "$mp" >/dev/null
check "marketplace entry has no version" $?
[ "$(jq -r .name "$pj")" = "second-brain" ]; check "plugin name" $?
jq -e '.plugins[] | select(.name=="second-brain") | .dependencies | map(.name+"@"+.marketplace) | sort == ["document-skills@anthropic-agent-skills","obsidian@obsidian-skills"]' "$mp" >/dev/null
check "second-brain depends on document-skills and obsidian" $?
jq -e '.allowCrossMarketplaceDependenciesOn | index("anthropic-agent-skills") and index("obsidian-skills")' "$mp" >/dev/null
check "marketplace allows the two dependency marketplaces" $?
[ "$(jq -r .version "$pj")" = "0.2.4" ]; check "plugin version 0.2.4" $?
jq -e '.hooks.SessionStart[0] | .matcher == "startup|resume|clear|compact|fork" and (.hooks[0].command | contains("session_start.py"))' "$p/hooks/hooks.json" >/dev/null
check "SessionStart hook is registered" $?
jq -e '.hooks.SessionStart[0].hooks[0].timeout == 60' "$p/hooks/hooks.json" >/dev/null
check "SessionStart hook timeout is 60" $?
jq -e '.hooks.SessionEnd[0].hooks[0].timeout == 30' "$p/hooks/hooks.json" >/dev/null
check "SessionEnd hook timeout is 30" $?
jq -e 'type == "array" and length > 0 and all(.[]; (.path | type == "string") and (.description | type == "string"))' "$p/templates/folders-default.json" >/dev/null
check "folders-default.json is a non-empty array of {path, description}" $?
[ ! -e "$p/templates/profiles" ]; check "templates/profiles does not exist" $?
jq -e '.extraKnownMarketplaces | keys == ["aether-labs"]' "$p/templates/settings.json" >/dev/null
check "settings template declares one marketplace" $?
jq -e '.permissions.deny | length == 6' "$p/templates/settings.json" >/dev/null; check "settings template has 6 deny rules" $?
jq -e '.behavior == "create" and .path == "_inbox"' "$p/templates/web-clipper-template.json" >/dev/null
check "web clipper template saves to _inbox" $?
jq -e '.userConfig.auto_commit | .type == "boolean" and .default == true' "$pj" >/dev/null
check "userConfig.auto_commit is boolean, default true" $?
jq -e '.hooks.UserPromptSubmit' "$p/hooks/hooks.json" >/dev/null
check "UserPromptSubmit recall hook is registered" $?
jq -e '.userConfig.recall.default == true' "$pj" >/dev/null
check "userConfig.recall defaults to true" $?
[ ! -e "$p/.mcp.json" ]; check "no .mcp.json (AC9)" $?
! grep -rEqi 'sentence[_-]transformers|ollama|faiss|chromadb|onnxruntime|openai' "$p/lib" "$p/bin" "$p/hooks" 2>/dev/null
check "no embedding/vector dependencies (AC9)" $?
skills="init capture ingest find lint"
for s in $skills; do
  f="$p/skills/$s/SKILL.md"
  [ -f "$f" ]; check "skills/$s/SKILL.md exists" $?
  grep -q "^name: $s$" "$f" 2>/dev/null; check "skills/$s frontmatter name" $?
  desc="$(awk '/^description: >/{f=1;next} f&&/^([a-z-]+:|---)/{exit} f{sub(/^  /,"");printf "%s ",$0}' "$f" 2>/dev/null)"
  [ "${#desc}" -ge 150 ] && [ "${#desc}" -le 400 ]; check "skills/$s description is 150-400 chars (${#desc})" $?
  [ "$({ wc -l < "$f"; } 2>/dev/null || echo 999)" -le 250 ]; check "skills/$s SKILL.md <= 250 lines" $?
done
[ "$(ls "$p/skills" 2>/dev/null | wc -l)" -eq 5 ]; check "exactly 5 skills" $?
[ ! -e "$p/skills/update" ] && [ ! -e "$p/skills/link" ]; check "skills/update and skills/link do not exist" $?
[ "$(cat "$p"/skills/*/SKILL.md | wc -c)" -le 12000 ]; check "SKILL.md files total <= 12000 bytes (AC2)" $?
[ -f "$p/skills/init/examples.md" ]; check "skills/init/examples.md exists" $?
grep -q '^disable-model-invocation: true$' "$p/skills/init/SKILL.md" 2>/dev/null
check "init is user-invoked only" $?
ing="$p/skills/ingest/SKILL.md"
for phrase in "never instructions" "Condense" "now or at the end" "--no-ask"; do
  grep -qF -- "$phrase" "$ing"; check "ingest holds the contract phrase: $phrase" $?
done
for word in "sb log" "sb index" "sb validate" "sb doctor" "sb review" "source_id" "guard" "companion" "_index.md"; do
  ! grep -qiF -- "$word" "$p"/skills/*/SKILL.md "$p/skills/init/examples.md" "$p/templates/CLAUDE.md"
  check "no skill or template mentions: $word" $?
done
tpl="$p/templates/CLAUDE.md"
[ "$(wc -l < "$tpl")" -lt 200 ]; check "vault CLAUDE.md template < 200 lines (AC1)" $?
[ "$(wc -m < "$tpl")" -le 3200 ]; check "vault CLAUDE.md template <= 3200 characters (AC10)" $?
for phrase in "never invent" "gap" "preamble" "recap" "[!agent]" "origin: agent" "_raw/"; do
  grep -qiF -- "$phrase" "$tpl"; check "template holds: $phrase" $?
done
[ -x "$p/bin/sb" ]; check "bin/sb is executable" $?

# No entry point names python3 outside the launcher (D61).
others="$(grep -rIl python3 "$p/hooks" "$p/bin" "$p/lib" --exclude-dir=__pycache__ 2>/dev/null | grep -v '/bin/sb-python$')"
[ -z "$others" ]; check "only bin/sb-python names python3" $?
[ -x "$p/bin/sb" ] && [ -x "$p/bin/sb-python" ]; check "bin/sb and bin/sb-python are executable" $?

# Every ${CLAUDE_PLUGIN_ROOT}/... path referenced anywhere must exist.
while IFS= read -r ref; do
  [ -e "$p/$ref" ]; check "referenced path exists: $ref" $?
done < <(grep -rhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./-]+' "$p" --exclude-dir=node_modules --include='*.md' --include='*.json' 2>/dev/null \
         | sed 's#\${CLAUDE_PLUGIN_ROOT}/##' | sort -u)

exit $fail
