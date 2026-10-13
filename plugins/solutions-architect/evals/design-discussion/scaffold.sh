#!/usr/bin/env bash
# Seeds a workspace whose requirements gate passed and that has no decisions yet.
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
m["gates"].pop("design", None)
m["decisions"], m["components"] = [], []
m["assumptions"]["usage"] = {}
json.dump(m, open(p, "w"), indent=2)
PY
