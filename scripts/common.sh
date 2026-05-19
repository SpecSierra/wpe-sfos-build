#!/bin/bash

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/versions.env"
source "${REPO_ROOT}/scripts/patches.sh"

export REPO_ROOT
export WORK="${WORK:-$(cd "${REPO_ROOT}/.." && pwd)}"
export BUILD_TOOLS="${BUILD_TOOLS:-${REPO_ROOT}}"
export BROWSER_SRC="${BROWSER_SRC:-${WORK}/sailfish-browser-wpe}"
export WPE_PREFIX="${WPE_PREFIX:-/opt/wpe-sfos}"
export SYSROOT="${SYSROOT:-/opt/sfos-sysroot}"
export NPROC="${NPROC:-$(nproc)}"

export LEGACY_WPE_SOURCE_DIR="${WORK}/wpewebkit-${LEGACY_WPEWEBKIT_VERSION}"
export TARGET_WPE_SOURCE_DIR="${WORK}/wpewebkit-${TARGET_WPEWEBKIT_VERSION}"
export QT5_PLUGIN_SOURCE_DIR_DEFAULT="${WORK}/wpewebkit-${LEGACY_QT5_PLUGIN_SOURCE_VERSION}"
