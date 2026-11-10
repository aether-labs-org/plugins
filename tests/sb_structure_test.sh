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
jq -e '.hooks.SessionStart[0] | .matcher == "startup|resume|clear|compact" and (.hooks[0].command | contains("session_start.py"))' "$p/hooks/hooks.json" >/dev/null
check "SessionStart hook is registered" $?
jq -e '.hooks.SessionEnd[0].hooks[0].timeout == 60' "$p/hooks/hooks.json" >/dev/null
check "SessionEnd hook timeout is 60" $?
for prof in personal work project squad; do
  jq -e '.name and .sync and (.folders | length > 0)' "$p/templates/profiles/$prof.json" >/dev/null
  check "profile $prof.json is valid" $?
done
jq -e '.sync == "squad"' "$p/templates/profiles/squad.json" >/dev/null; check "squad profile syncs" $?
jq -e '.extraKnownMarketplaces | keys | sort == ["aether-labs","anthropic-agent-skills","obsidian-skills"]' "$p/templates/settings.json" >/dev/null
check "settings template declares the three marketplaces" $?
jq -e '.permissions.deny | length == 5' "$p/templates/settings.json" >/dev/null; check "settings template has 5 deny rules" $?
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
skills="init capture ingest find link update lint"
for s in $skills; do
  f="$p/skills/$s/SKILL.md"
  [ -f "$f" ]; check "skills/$s/SKILL.md exists" $?
  grep -q "^name: $s$" "$f" 2>/dev/null; check "skills/$s frontmatter name" $?
  desc="$(awk '/^description: >/{f=1;next} f&&/^([a-z-]+:|---)/{exit} f{sub(/^  /,"");printf "%s ",$0}' "$f" 2>/dev/null)"
  [ "${#desc}" -ge 150 ] && [ "${#desc}" -le 400 ]; check "skills/$s description is 150-400 chars (${#desc})" $?
  [ "$({ wc -l < "$f"; } 2>/dev/null || echo 999)" -le 250 ]; check "skills/$s SKILL.md <= 250 lines" $?
done
[ "$(ls "$p/skills" 2>/dev/null | wc -l)" -eq 7 ]; check "exactly 7 skills" $?
grep -q '^disable-model-invocation: true$' "$p/skills/init/SKILL.md" 2>/dev/null
check "init is user-invoked only" $?
[ "$(wc -l < "$p/templates/CLAUDE.md")" -lt 200 ]; check "vault CLAUDE.md template < 200 lines (AC1)" $?
[ -x "$p/bin/sb" ]; check "bin/sb is executable" $?

# Obsidian companion bundle (spec 7.2): sb init copies obsidian/dist into the vault.
dist="$p/obsidian/dist"
for f in main.js manifest.json styles.css; do
  [ -s "$dist/$f" ]; check "companion dist/$f exists" $?
done
jq -e '.id == "second-brain-companion" and .isDesktopOnly == false' "$dist/manifest.json" >/dev/null
check "companion manifest: id second-brain-companion, isDesktopOnly false" $?
cmp -s "$dist/manifest.json" "$p/obsidian/manifest.json"; check "companion dist manifest matches the source manifest" $?
[ ! -e "$p/obsidian/main.js" ]; check "no main.js outside dist/ in the companion" $?

# Every ${CLAUDE_PLUGIN_ROOT}/... path referenced anywhere must exist.
while IFS= read -r ref; do
  [ -e "$p/$ref" ]; check "referenced path exists: $ref" $?
done < <(grep -rhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./-]+' "$p" --exclude-dir=node_modules --include='*.md' --include='*.json' 2>/dev/null \
         | sed 's#\${CLAUDE_PLUGIN_ROOT}/##' | sort -u)

exit $fail
