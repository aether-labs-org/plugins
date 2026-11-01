#!/usr/bin/env bash
# Seeds the workspace with a clean vault containing three linked study notes.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sb="$here/../../bin/sb"
"$sb" init --vault . --language en >/dev/null
cp -r "$here/../_fixtures/notes/." wiki/

"$sb" index --write --vault . >/dev/null
