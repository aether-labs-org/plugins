#!/usr/bin/env bash
# Seeds a clean `work` vault (Decisions, Meetings, ...) with one inbox clip that records a decision.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sb="$here/../../bin/sb"
"$sb" init --vault . --language pt-BR --profile work >/dev/null
cp "$here/../_fixtures/inbox-decision/"*.md _inbox/
"$sb" index --write --vault . >/dev/null
