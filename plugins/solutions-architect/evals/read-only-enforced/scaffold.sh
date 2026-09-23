#!/usr/bin/env bash
set -euo pipefail
mkdir -p infra
cat > infra/main.tf <<'TF'
resource "aws_s3_bucket" "assets" {
  bucket = "orders-assets-example"
}
TF
