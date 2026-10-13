#!/usr/bin/env bash
# Seeds the designed workspace and replaces the compute decision with EKS + Strimzi Kafka + Datadog.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -r "$here/../_fixtures/workspace/architecture" .
cp "$here/0003-platform.md" architecture/decisions/
sed -i "s/^- Status: accepted$/- Status: superseded by ADR-0003/" architecture/decisions/0001-compute.md
python3 - <<'PY'
import json
p = "architecture/manifest.json"
m = json.load(open(p))
for d in m["decisions"]:
    if d["id"] == "ADR-0001":
        d["status"] = "superseded"
m["decisions"].append({"id": "ADR-0003", "file": "decisions/0003-platform.md", "status": "accepted",
                       "supersedes": "ADR-0001", "addresses": ["NFR-001", "NFR-002"]})
m["components"] = [c for c in m["components"] if c["id"] == "orders-db"] + [
    {"id": "orders-eks", "service": "Amazon EKS", "decision": "ADR-0003", "terraform": [], "diagrams": ["topology"]},
    {"id": "order-api", "service": "Kubernetes Deployment on EKS", "decision": "ADR-0003", "terraform": [], "diagrams": ["topology"]},
    {"id": "order-events", "service": "Apache Kafka (Strimzi on EKS)", "decision": "ADR-0003", "terraform": [], "diagrams": ["topology"]},
    {"id": "observability", "service": "Datadog (SaaS)", "decision": "ADR-0003", "terraform": [], "diagrams": ["topology"]},
]
m["assumptions"]["usage"] = {}
json.dump(m, open(p, "w"), indent=2)
PY
