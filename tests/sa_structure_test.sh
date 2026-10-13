#!/usr/bin/env bash
# Structural checks for the solutions-architect plugin (plan Tasks 1, 8-14).
set -uo pipefail
fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
root="$(cd "$(dirname "$0")/.." && pwd)"
p="$root/plugins/solutions-architect"
mp="$root/.claude-plugin/marketplace.json"
pj="$p/.claude-plugin/plugin.json"

jq -e '.plugins[] | select(.name == "solutions-architect" and .source == "./plugins/solutions-architect")' "$mp" >/dev/null
check "marketplace lists solutions-architect" $?
jq -e '.allowCrossMarketplaceDependenciesOn | index("claude-plugins-official")' "$mp" >/dev/null
check "marketplace allows the claude-plugins-official dependency" $?
jq -e '.allowCrossMarketplaceDependenciesOn | index("drawio") | not' "$mp" >/dev/null
check "drawio is not a declared dependency (D20)" $?
[ "$(jq -r .name "$pj")" = "solutions-architect" ]; check "plugin name" $?
jq -e '.plugins[] | select(.name == "solutions-architect") | .dependencies == [{"name": "aws-core", "marketplace": "claude-plugins-official", "version": "^1.1.0"}]' "$mp" >/dev/null
check "marketplace entry depends on aws-core ^1.1.0 only (D4, D24)" $?
jq -e 'has("dependencies") | not' "$pj" >/dev/null
check "plugin.json declares no dependencies (D24: evals load the plugin directory alone)" $?
! grep -q '@latest' "$p/.mcp.json"; check "no @latest in .mcp.json" $?
jq -e '.mcpServers | keys == ["aws-pricing", "terraform"]' "$p/.mcp.json" >/dev/null; check "mcp servers are aws-pricing and terraform" $?
jq -e '.hooks.PreToolUse[0].matcher == "Bash|mcp__.*run_script.*"' "$p/hooks/hooks.json" >/dev/null; check "hook matcher" $?

skills="architect requirements design diagram finops iac docs review"
for s in $skills; do
  f="$p/skills/$s/SKILL.md"
  [ -f "$f" ]; check "skills/$s/SKILL.md exists" $?
  grep -q "^name: $s$" "$f"; check "skills/$s frontmatter name" $?
  desc="$(awk '/^description: >/{f=1;next} f&&/^([a-z-]+:|---)/{exit} f{sub(/^  /,"");printf "%s ",$0}' "$f")"
  [ "${#desc}" -ge 150 ] && [ "${#desc}" -le 400 ]; check "skills/$s description is 150-400 chars (${#desc})" $?
  [ "$(wc -l < "$f")" -le 250 ]; check "skills/$s SKILL.md <= 250 lines" $?
done
[ "$(ls "$p/skills" | wc -l)" -eq 8 ]; check "exactly 8 skills in Phase 1" $?
for a in architecture-reviewer finops-analyst; do
  grep -q "^name: $a$" "$p/agents/$a.md"; check "agents/$a frontmatter" $?
done

# Every ${CLAUDE_PLUGIN_ROOT}/... path and every relative references/ assets/ link must exist.
missing=0
while IFS= read -r ref; do
  [ -e "$p/$ref" ] || { echo "    missing: $ref"; missing=1; }
done < <(grep -rhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./-]+' "$p" --include='*.md' --include='*.json' | sed 's#^${CLAUDE_PLUGIN_ROOT}/##' | sort -u)
for s in $skills; do
  while IFS= read -r ref; do
    [ -e "$p/skills/$s/$ref" ] || { echo "    missing: skills/$s/$ref"; missing=1; }
  done < <(grep -oE '`(references|assets)/[A-Za-z0-9_./-]+`' "$p/skills/$s/SKILL.md" | tr -d '`' | sort -u)
done
check "every referenced plugin path exists" $missing

bad=0
while IFS= read -r s; do grep -qx "$s" "$p/providers/aws/aws4-allowlist.txt" || { echo "    not in allowlist: $s"; bad=1; }; done \
  < <(grep -rhoE 'mxgraph\.aws4\.[A-Za-z0-9_]+' "$p/skills" | sort -u)
check "every AWS4 shape named in the skills is in the allowlist" $bad

bad=0
while IFS= read -r s; do grep -qx "mxgraph.kubernetes.$s" "$p/providers/kubernetes/kubernetes-allowlist.txt" || { echo "    not in kubernetes allowlist: $s"; bad=1; }; done \
  < <(grep -rhoE 'prIcon=[a-z_0-9]+' "$p/skills" | sed 's/prIcon=//' | sort -u)
check "every Kubernetes icon named in the skills is in the allowlist" $bad

bad=0
while IFS= read -r s; do python3 -c 'import json,sys; sys.exit(sys.argv[2] not in json.load(open(sys.argv[1])))' "$p/providers/icons/catalog.json" "$s" || { echo "    not in icon catalog: $s"; bad=1; }; done \
  < <(grep -rhoE 'sa_icon="[a-z0-9]+"' "$p/skills" | sed 's/sa_icon="//; s/"//' | sort -u)
while IFS= read -r s; do [ -s "$p/providers/icons/svg/$s.svg" ] || { echo "    missing svg: $s"; bad=1; }; done \
  < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))))' "$p/providers/icons/catalog.json")
check "every sa_icon named in the skills is in the catalog and has an svg" $bad

python3 - "$p/providers/icons/catalog.json" "$p/skills/diagram/references/third-party-icons.md" <<'EOF'
import json, re, sys
catalog = set(json.load(open(sys.argv[1])))
rows = [l for l in open(sys.argv[2]) if re.match(r"\| (Observability|Streaming|Platform)", l)]
table = {s for l in rows for s in re.findall(r"`([a-z0-9]+)`", l)}
for s in sorted(table - catalog): print(f"    in the table, not in the catalog: {s}")
for s in sorted(catalog - table): print(f"    in the catalog, not in the table: {s}")
sys.exit(table != catalog)
EOF
check "third-party icon table matches the catalog" $?

! grep -rn '\.\./\.\.' "$p" --include='*.md' --include='*.json' >/dev/null; check "plugin does not escape its directory" $?
for f in $(find "$p" -name '*.py'); do python3 -m py_compile "$f" || { echo "    $f"; fail=1; }; done
check "python scripts compile" 0
exit $fail
