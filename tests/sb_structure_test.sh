#!/usr/bin/env bash
# Structural checks for the second-brain plugin (spec sections 3, 6, 10).
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
[ "$(jq -r .version "$pj")" = "0.1.0" ]; check "plugin version 0.1.0" $?
jq -e '.userConfig.auto_commit | .type == "boolean" and .default == true' "$pj" >/dev/null
check "userConfig.auto_commit is boolean, default true" $?
[ ! -e "$p/.mcp.json" ]; check "no .mcp.json (AC9)" $?
! grep -rEqi 'sentence[_-]transformers|ollama|faiss|chromadb|onnxruntime|openai' "$p/lib" "$p/bin" "$p/hooks" 2>/dev/null
check "no embedding/vector dependencies (AC9)" $?

validate_out="$(claude plugin validate "$p" --strict 2>&1)"; validate_status=$?
check "claude plugin validate --strict" $validate_status
if [ "$validate_status" -ne 0 ]; then
  echo "       claude $(claude --version 2>&1 | head -1)"
  printf '%s\n' "$validate_out" | sed 's/^/       /'
fi
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

# Every ${CLAUDE_PLUGIN_ROOT}/... path referenced anywhere must exist.
while IFS= read -r ref; do
  [ -e "$p/$ref" ]; check "referenced path exists: $ref" $?
done < <(grep -rhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./-]+' "$p" --include='*.md' --include='*.json' 2>/dev/null \
         | sed 's#\${CLAUDE_PLUGIN_ROOT}/##' | sort -u)

exit $fail
