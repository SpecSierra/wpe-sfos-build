#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${SCRIPT_DIR}/common.sh"

cleanup_target() {
    rm -rf "${REPO_ROOT}/adblock-engine/target"
}
trap cleanup_target EXIT

echo ""
echo "--- Building adblock-rust engine ---"

if [ -f "${HOME}/.cargo/env" ]; then
    source "${HOME}/.cargo/env"
elif [ -n "${SUDO_USER:-}" ] && [ -f "/home/${SUDO_USER}/.cargo/env" ]; then
    source "/home/${SUDO_USER}/.cargo/env"
fi

cd "${REPO_ROOT}/adblock-engine"
cargo build --release

mkdir -p "${WPE_PREFIX}/lib"
cp -a target/release/libatlantic_adblock.so "${WPE_PREFIX}/lib/"

echo "  libatlantic_adblock.so staged to ${WPE_PREFIX}/lib/"
