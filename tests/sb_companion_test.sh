#!/usr/bin/env bash
# Builds and tests the Obsidian companion (plugins/second-brain/obsidian) and checks that the
# committed bundle in dist/ is up to date. Skips when node or npm is missing.
set -uo pipefail
fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
root="$(cd "$(dirname "$0")/.." && pwd)"
dir="$root/plugins/second-brain/obsidian"

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "  skip companion (node not found)"
  exit 0
fi

if [ -d "$dir/node_modules" ]; then
  echo "  ok   companion dependencies present (node_modules reused)"
else
  log="$(npm ci --prefix "$dir" --no-audit --no-fund 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || printf '%s\n' "$log" | tail -20 | sed 's/^/       /'
  check "npm ci" "$rc"
fi
npm test --prefix "$dir" >/dev/null 2>&1; check "companion unit tests (vitest)" $?
npm run build --prefix "$dir" >/dev/null 2>&1; check "companion build" $?
git -C "$root" diff --exit-code --quiet -- plugins/second-brain/obsidian/dist
check "committed dist/ is up to date (run npm run build in plugins/second-brain/obsidian and commit)" $?
exit $fail
