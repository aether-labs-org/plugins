#!/usr/bin/env bash
# Sourced by keel_*_test.sh. Not a test itself.
KEEL="$(cd "$(dirname "${BASH_SOURCE[0]}")/../plugins/keel-harness" && pwd)"
STUBS="$(cd "$(dirname "${BASH_SOURCE[0]}")/fixtures/keel/stubs" && pwd)"
FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/fixtures/keel" && pwd)"
export KEEL STUBS FIXTURES
# KEEL_ENGINE=cli runs every gate and sensor through the keel CLI (cli/keel, built by
# `make -C cli/keel build`) instead of scripts/gate.sh; the default is the bash engine.
KEEL_ENGINE="${KEEL_ENGINE:-bash}"
RUN_SENSOR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/keel_run_sensor.sh"
export KEEL_ENGINE RUN_SENSOR
if [ "$KEEL_ENGINE" = cli ]; then
  KEEL_BIN="${KEEL_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/cli/keel/dist/keel}"
  KEEL_SUMS="$(dirname "$KEEL_BIN")/SHA256SUMS"
  export KEEL_BIN KEEL_SUMS
fi
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
# install_asset REPO SRC_REL DEST_REL  (SRC_REL relative to $KEEL/skills/)
# Under KEEL_ENGINE=cli, gate.sh is replaced by a shim that runs `keel gate` on the same layout.
install_asset() {
  mkdir -p "$(dirname "$1/$3")"
  if [ "$KEEL_ENGINE" = cli ] && [ "$2" = build/assets/gate.sh ]; then
    printf '%s\n' '#!/usr/bin/env bash' 'cd "$(dirname "$0")/.." || exit 1' \
      '"$KEEL_BIN" import --force --sums "$KEEL_SUMS" >/dev/null || exit 3' 'exec "$KEEL_BIN" gate "$@"' > "$1/$3"
    chmod +x "$1/$3"; return
  fi
  cp "$KEEL/skills/$2" "$1/$3" && chmod +x "$1/$3"
}
# use_stub REPO TOOL DEST_REL
use_stub() {
  mkdir -p "$(dirname "$1/$3")"
  cp "$STUBS/$2" "$1/$3" && chmod +x "$1/$3"
}
# finish: exit with accumulated status
finish() { exit $_keel_fail; }
