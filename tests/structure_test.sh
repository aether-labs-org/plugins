#!/usr/bin/env bash
# Structural checks for the marketplace and the keel-harness plugin.
set -uo pipefail
fail=0
check() { # check <description> <condition-exit-code>
  if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi
}
root="$(cd "$(dirname "$0")/.." && pwd)"
mp="$root/.claude-plugin/marketplace.json"
pj="$root/plugins/keel-harness/.claude-plugin/plugin.json"

jq -e . "$mp" >/dev/null 2>&1; check "marketplace.json is valid JSON" $?
[ "$(jq -r .name "$mp" 2>/dev/null)" = "aether-labs" ]; check "marketplace name is aether-labs" $?
[ -n "$(jq -r '.owner.name // empty' "$mp" 2>/dev/null)" ]; check "marketplace has owner.name" $?
[ "$(jq -r '.plugins[0].source' "$mp" 2>/dev/null)" = "./plugins/keel-harness" ]; check "plugin source path" $?
[ -d "$root/plugins/keel-harness" ]; check "plugin source path exists" $?
[ "$(jq -r '.plugins[0].version // "unset"' "$mp" 2>/dev/null)" = "unset" ]; check "no version in marketplace entry" $?

jq -e . "$pj" >/dev/null 2>&1; check "plugin.json is valid JSON" $?
[ "$(jq -r .name "$pj" 2>/dev/null)" = "keel-harness" ]; check "plugin name is keel-harness" $?

for forbidden in hooks .mcp.json bin commands; do
  [ ! -e "$root/plugins/keel-harness/$forbidden" ]
  check "plugin has no $forbidden (spec 9)" $?
done

for s in assess build doctor; do
  f="$root/plugins/keel-harness/skills/$s/SKILL.md"
  [ -f "$f" ]; check "skills/$s/SKILL.md exists" $?
  grep -q "^name: $s$" "$f" 2>/dev/null; check "skills/$s frontmatter name" $?
  grep -q "^description: >" "$f" 2>/dev/null; check "skills/$s frontmatter description" $?
done

# The plugin must not reference anything outside its own directory.
! grep -rn '\.\./\.\.' "$root/plugins/keel-harness" --include='*.md' --include='*.json' >/dev/null 2>&1
check "plugin does not escape its directory" $?

exit $fail
