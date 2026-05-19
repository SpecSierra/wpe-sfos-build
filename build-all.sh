#!/bin/bash
# Master build script for WPE SFOS — native aarch64 Ubuntu 24.04
# Logs to /tmp/wpe-build.log
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/scripts/common.sh"

echo "================================================================"
echo "=== WPE SFOS Build started at $(date)"
echo "=== CPUs: ${NPROC}"
echo "=== Scripted baseline: SFOS ${SFOS_SYSROOT_VERSION} / WPE WebKit ${LEGACY_WPEWEBKIT_VERSION}"
echo "=== Migration target: SFOS ${TARGET_SFOS_VERSION} / WPE WebKit ${TARGET_WPEWEBKIT_VERSION}"
echo "================================================================"

bash "${SCRIPT_DIR}/scripts/bootstrap-host.sh"
bash "${SCRIPT_DIR}/scripts/build-engine.sh"
bash "${SCRIPT_DIR}/scripts/build-webkit.sh"
bash "${SCRIPT_DIR}/scripts/build-ui.sh"
bash "${SCRIPT_DIR}/scripts/package-rpms.sh"

echo ""
echo "================================================================"
echo "=== Build COMPLETE at $(date)"
echo "=== RPMs in /tmp/wpe-sfos-rpms/:"
ls -lh /tmp/wpe-sfos-rpms/*.rpm
echo "================================================================"
