#!/usr/bin/env bash
# Seeds a vault with a broken link and a note without summary.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sb="$here/../../bin/sb"
"$sb" init --vault . --language en >/dev/null
cp -r "$here/../_fixtures/notes-broken/." wiki/

"$sb" index --write --vault . >/dev/null
