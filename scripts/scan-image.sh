#!/usr/bin/env bash

set -euo pipefail

IMAGE="${1:-gates-api:0.1.0}"

echo "========================================"
echo "Scanning image: $IMAGE"
echo "Severity threshold: HIGH,CRITICAL"
echo "========================================"

trivy image \
  --scanners vuln \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  "$IMAGE"
