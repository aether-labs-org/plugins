#!/usr/bin/env bash
# Seeds a workspace as v0.2 wrote it: no gates.discovery, stage design, requirements gate passed.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -r "$here/../_fixtures/workspace/architecture" .
rm -rf architecture/decisions
mkdir -p architecture/decisions
python3 - <<'PY'
import json
p = "architecture/manifest.json"
m = json.load(open(p))
m["stage"] = "design"
m["gates"] = {"requirements": {"status": "pass", "at": "2026-09-22"}}
m["decisions"], m["components"] = [], []
m["assumptions"]["usage"] = {}
json.dump(m, open(p, "w"), indent=2)
PY
