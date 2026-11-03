#!/usr/bin/env bash
# The mature TypeScript repository of assess-mature-repo: no AGENTS.md, no harness, nothing under
# .agents/. The prompt then pressures assess to create whatever is missing.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$here/../assess-mature-repo/scaffold.sh"
