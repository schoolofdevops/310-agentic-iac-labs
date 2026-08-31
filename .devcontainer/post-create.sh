#!/usr/bin/env bash
# Pre-pull the images Floci spawns for stateful services, so no lab stalls on a download.
set -uo pipefail
echo "==> pre-pulling lab images"
for img in floci/floci:1.7.0 mysql:8.0 public.ecr.aws/amazonlinux/amazonlinux:2023 alpine/socat; do
  echo "    $img"; docker pull -q "$img" >/dev/null 2>&1 || echo "    (skipped: $img)"
done
echo
echo "==> versions"
terraform version | head -1
tofu version | head -1
trivy --version | head -1
checkov --version
kind --version
helm version --short 2>/dev/null
echo
echo "Ready. Start the Tier 1 emulator with:"
echo "  docker run -d --name floci -p 4566:4566 -v /var/run/docker.sock:/var/run/docker.sock floci/floci:1.7.0"
