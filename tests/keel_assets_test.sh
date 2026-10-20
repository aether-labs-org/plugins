#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
n=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  n=$((n+1))
  rel="${f#"$KEEL"/}"
  shellcheck -S warning "$f" >/dev/null 2>&1; check "shellcheck: $rel" $?
  ! grep -nE 'declare -A|mapfile|readarray|\$\{[A-Za-z_]+(,,|\^\^)\}|(^|[^a-z_])jq( |$)' "$f" >/dev/null; check "bash3.2/no-jq: $rel" $?
  case "$f" in
    */skills/build/assets/*|*/skills/rules/assets/sensors/*)
      ! grep -nE 'CLAUDE_|keel-harness/' "$f" | grep -v 'Managed by keel-harness' >/dev/null; check "no plugin paths: $rel" $? ;;
  esac
done <<EOL
$(find "$KEEL"/skills/*/assets -type f -name '*.sh' | sort)
EOL
[ "$n" -gt 0 ]; check "at least one asset exists" $?
finish
