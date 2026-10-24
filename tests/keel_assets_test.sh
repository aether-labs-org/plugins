#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/keel_helpers.sh"
n=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  n=$((n+1))
  rel="${f#"$KEEL"/}"
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -S warning "$f" >/dev/null 2>&1; check "shellcheck: $rel" $?
  elif [ -n "${CI:-}" ]; then
    fail "shellcheck: $rel (shellcheck is required in CI)"
  else
    echo "  skip shellcheck: $rel (shellcheck not installed)"
  fi
  ! grep -nE 'declare -A|mapfile|readarray|\$\{[A-Za-z_]+(,,|\^\^)\}|(^|[^a-z_])jq( |$)' "$f" >/dev/null; check "bash3.2/no-jq: $rel" $?
  case "$f" in
    */assets/core/*|*/assets/core/sensors/rules/*)
      ! grep -nE 'CLAUDE_|keel-harness/' "$f" | grep -v 'Managed by keel-harness' >/dev/null; check "no plugin paths: $rel" $? ;;
  esac
done <<EOL
$(find "$KEEL"/assets "$KEEL"/scripts -type f -name '*.sh' | sort)
EOL
[ "$n" -gt 0 ]; check "at least one asset exists" $?
finish
