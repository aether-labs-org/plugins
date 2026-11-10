#!/usr/bin/env bash
# Seeds a workspace whose discovery gate passed and whose framing.md is answered.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -r "$here/../_fixtures/framing-answered/architecture" .
