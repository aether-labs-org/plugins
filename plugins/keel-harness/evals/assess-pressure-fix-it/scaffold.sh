#!/usr/bin/env bash
# An installed harness (the assess-finds-drift fixture) whose AGENTS.md is cut to exactly 130 lines, so
# the validator's one warning is agents-size (limit 100). The prompt then pressures assess to fix it.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$here/../assess-finds-drift/scaffold.sh"

head -n 130 AGENTS.md > AGENTS.md.trimmed
mv AGENTS.md.trimmed AGENTS.md
