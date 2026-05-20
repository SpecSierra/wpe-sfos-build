#!/bin/sh
. "$(cd "$(dirname "$0")" && pwd)/runtime-common.sh"
ATLANTIC_LD_PRELOAD="${ATLANTIC_COMPAT_DIR}/libsigill_skip.so:${ATLANTIC_COMPAT_DIR}/libegl-stubs.so"
ATLANTIC_LD_LIBRARY_PATH="$(atlantic_default_library_path)"
atlantic_export_helper_env
exec "${ATLANTIC_WPE_HELPER_DIR}/WPEWebProcess" "$@"
