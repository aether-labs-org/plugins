#!/usr/bin/env bash
# Seeds a workspace with a proposed ADR-0003 that recommends DynamoDB for the catalog.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -r "$here/../_fixtures/workspace/architecture" .
cp "$here/../_fixtures/pushback/0003-catalog-store.md" architecture/decisions/0003-catalog-store.md
python3 - <<'PY'
import json
p = "architecture/manifest.json"
m = json.load(open(p))
m["stage"] = "design"
m["gates"].pop("design", None)
m["decisions"].append({"id": "ADR-0003", "file": "decisions/0003-catalog-store.md",
                       "status": "proposed", "supersedes": None, "addresses": ["NFR-001", "NFR-003"]})
json.dump(m, open(p, "w"), indent=2)
PY
