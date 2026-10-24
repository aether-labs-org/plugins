#!/usr/bin/env bash
# Sourced by keel_*_test.sh. Not a test itself.
KEEL="$(cd "$(dirname "${BASH_SOURCE[0]}")/../plugins/keel-harness" && pwd)"
STUBS="$(cd "$(dirname "${BASH_SOURCE[0]}")/fixtures/keel/stubs" && pwd)"
FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/fixtures/keel" && pwd)"
export KEEL STUBS FIXTURES
_keel_fail=0
check() { if [ "$2" -eq 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; _keel_fail=1; fi; }
fail() { echo "  FAIL $1"; _keel_fail=1; }
_keel_tmps=""
_keel_cleanup() { for d in $_keel_tmps; do rm -rf "$d"; done; }
trap _keel_cleanup EXIT
# new_repo [--no-commit] -> prints path of a fresh git repo (removed on EXIT)
new_repo() {
  local d
  d="$(mktemp -d)"
  _keel_tmps="$_keel_tmps $d"
  (
    cd "$d" || exit 1
    git init -q . && git config user.email t@t && git config user.name t
    git config core.quotepath off
    if [ "${1:-}" != "--no-commit" ]; then
      echo seed > .seed && git add .seed && git commit -q -m seed
    fi
  )
  printf '%s\n' "$d"
}
# install_asset REPO SRC_REL DEST_REL  (SRC_REL relative to $KEEL, the plugin root)
install_asset() {
  mkdir -p "$(dirname "$1/$3")"
  cp "$KEEL/$2" "$1/$3" && chmod +x "$1/$3"
}
# use_stub REPO TOOL DEST_REL
use_stub() {
  mkdir -p "$(dirname "$1/$3")"
  cp "$STUBS/$2" "$1/$3" && chmod +x "$1/$3"
}
# finish: exit with accumulated status
finish() { exit $_keel_fail; }
