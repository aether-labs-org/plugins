#!/usr/bin/env bash
# Structural checks for the marketplace and the baymax plugin.
set -uo pipefail
fail=0
check() { # check <description> <condition-exit-code>
  if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi
}
root="$(cd "$(dirname "$0")/.." && pwd)"
mp="$root/.claude-plugin/marketplace.json"
pj="$root/plugins/baymax/.claude-plugin/plugin.json"

jq -e . "$mp" >/dev/null 2>&1; check "marketplace.json is valid JSON" $?
[ "$(jq -r .name "$mp" 2>/dev/null)" = "aether-labs" ]; check "marketplace name is aether-labs" $?
[ -n "$(jq -r '.owner.name // empty' "$mp" 2>/dev/null)" ]; check "marketplace has owner.name" $?
[ "$(jq -r '.plugins[0].source' "$mp" 2>/dev/null)" = "./plugins/baymax" ]; check "plugin source path" $?
[ -d "$root/plugins/baymax" ]; check "plugin source path exists" $?
[ "$(jq -r '.plugins[0].version // "unset"' "$mp" 2>/dev/null)" = "unset" ]; check "no version in marketplace entry" $?

jq -e . "$pj" >/dev/null 2>&1; check "plugin.json is valid JSON" $?
[ "$(jq -r .name "$pj" 2>/dev/null)" = "baymax" ]; check "plugin name is baymax" $?
[ "$(jq -r .version "$pj" 2>/dev/null)" = "0.5.0-rc.1" ]; check "plugin version is 0.5.0-rc.1" $?
desc="$(jq -r .description "$pj" 2>/dev/null)"
[ -n "$desc" ] && [ "$(jq -r '.plugins[0].description' "$mp" 2>/dev/null)" = "$desc" ] && grep -qF "$desc" "$root/README.md"; check "plugin.json, marketplace.json and the root README carry the same description" $?

for forbidden in hooks .mcp.json bin commands; do
  [ ! -e "$root/plugins/baymax/$forbidden" ]
  check "plugin has no $forbidden (spec 9)" $?
done

for s in harness; do
  f="$root/plugins/baymax/skills/$s/SKILL.md"
  [ -f "$f" ]; check "skills/$s/SKILL.md exists" $?
  grep -q "^name: $s$" "$f" 2>/dev/null; check "skills/$s frontmatter name" $?
  grep -q "^description: " "$f" 2>/dev/null; check "skills/$s frontmatter description" $?
done
[ "$(ls "$root/plugins/baymax/skills" | tr '\n' ' ')" = "harness " ]; check "the plugin has one skill" $?

# The plugin must not reference anything outside its own directory.
! grep -rn '\.\./\.\.' "$root/plugins/baymax" --include='*.md' --include='*.json' >/dev/null 2>&1
check "plugin does not escape its directory" $?

exit $fail
