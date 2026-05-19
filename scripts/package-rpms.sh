#!/bin/bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

echo ""
echo "--- [13] Building RPMs ---"
bash "${BUILD_TOOLS}/build-rpms-native.sh"
