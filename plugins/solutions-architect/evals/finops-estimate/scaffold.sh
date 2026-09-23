#!/usr/bin/env bash
# Seeds a Terraform plan JSON, the manifest and recorded Price List responses (no network in runs).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fx="$here/../_fixtures/finops"
mkdir -p architecture/finops infra
cp "$fx/manifest.json" architecture/manifest.json
cp "$fx/plan.json" infra/plan.json
cp -r "$fx/pricing-cache" architecture/finops/pricing-cache
