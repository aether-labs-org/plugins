#!/usr/bin/env bash
# Seeds the workspace with a designed architecture (requirements, two ADRs, manifest).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -r "$here/../_fixtures/workspace/architecture" .
