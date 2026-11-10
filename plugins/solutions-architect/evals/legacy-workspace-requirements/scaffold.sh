#!/usr/bin/env bash
# Seeds a workspace as v0.2 wrote it at its first stage: no gates at all, stage requirements,
# no requirements recorded yet.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -r "$here/../_fixtures/workspace/architecture" .
rm -rf architecture/decisions architecture/requirements.md
mkdir -p architecture/decisions
python3 - <<'PY'
import json
p = "architecture/manifest.json"
m = json.load(open(p))
m["stage"] = "requirements"
m["gates"] = {}
m["requirements"], m["decisions"], m["components"] = [], [], []
m["assumptions"]["usage"] = {}
json.dump(m, open(p, "w"), indent=2)
PY
