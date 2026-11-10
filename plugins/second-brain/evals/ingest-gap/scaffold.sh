#!/usr/bin/env bash
# Seeds a clean pt-BR vault with one inbox clip that states a decision but not its date or its reason.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sb="$here/../../bin/sb"
"$sb" init --vault . --language pt-BR >/dev/null
cp "$here/../_fixtures/inbox-gap/"*.md _inbox/
