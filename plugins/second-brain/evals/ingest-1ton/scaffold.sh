#!/usr/bin/env bash
# Seeds a clean vault with three human notes and one multi-idea web clip in the inbox.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sb="$here/../../bin/sb"
"$sb" init --vault . --language en >/dev/null
cp -r "$here/../_fixtures/notes/." wiki/
cp "$here/../_fixtures/inbox-multi/"*.md _inbox/
