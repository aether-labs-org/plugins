#!/usr/bin/env bash
# Seeds a clean vault plus one inbox item to ingest.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sb="$here/../../bin/sb"
"$sb" init --vault . --language en >/dev/null
cp -r "$here/../_fixtures/notes/." wiki/
cp "$here/../_fixtures/inbox/"*.md _inbox/
"$sb" index --write --vault . >/dev/null
