#!/usr/bin/env bash
# Seeds a workspace with an answered framing.md (candidate A cites a not-consulted reference).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -r "$here/../_fixtures/framing-answered/architecture" .
