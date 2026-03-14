#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Debug}"
xcodebuild -scheme Portu -configuration "$CONFIG" build
echo "✓ Build complete ($CONFIG)"
