#!/usr/bin/env bash
# Seeds a designed workspace whose framing.md has the anti-goal "the team must not operate
# Kubernetes" and whose accepted ADR-0001 chooses Amazon EKS.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -r "$here/../_fixtures/workspace/architecture" .
cp "$here/../_fixtures/framing-answered/architecture/framing.md" architecture/framing.md
cp "$here/../_fixtures/framing-anti-goal/0001-compute.md" architecture/decisions/0001-compute.md
python3 - <<'PY'
import json
p = "architecture/manifest.json"
m = json.load(open(p))
m["stage"] = "review"
for g in ("discovery", "requirements", "design", "diagram", "finops-compare", "iac", "finops-estimate", "docs"):
    m["gates"][g] = {"status": "pass", "at": "2026-11-06"}
m["decisions"][0]["addresses"] = ["NFR-001", "NFR-002"]
for c in m["components"]:
    if c["id"] == "order-api":
        c["service"] = "Amazon EKS"
json.dump(m, open(p, "w"), indent=2)
PY
