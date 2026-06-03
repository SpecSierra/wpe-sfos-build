#!/bin/bash

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/versions.env"
source "${REPO_ROOT}/scripts/patches.sh"

export REPO_ROOT
export WORK="${WORK:-$(cd "${REPO_ROOT}/.." && pwd)}"
export BUILD_TOOLS="${BUILD_TOOLS:-${REPO_ROOT}}"
export BROWSER_SRC="${BROWSER_SRC:-${WORK}/atlantic-browser}"
export CI_CACHE_ROOT="${CI_CACHE_ROOT:-/opt/github-runner/cache/atlantic-build}"
export WPE_PREFIX="${WPE_PREFIX:-/opt/wpe-sfos}"
export SYSROOT="${SYSROOT:-/opt/sfos-sysroot}"
export NPROC="${NPROC:-$(nproc)}"
export CCACHE_DIR="${CCACHE_DIR:-/opt/github-runner/cache/ccache}"
export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-40G}"
export CCACHE_BASEDIR="${CCACHE_BASEDIR:-${CI_CACHE_ROOT:-${CI_ROOT:-${WORK}}}}"
export CCACHE_NOHASHDIR="${CCACHE_NOHASHDIR:-1}"

if [ -d /usr/lib/ccache ]; then
    export PATH="/usr/lib/ccache:${PATH}"
fi

export LEGACY_WPE_SOURCE_DIR="${WORK}/wpewebkit-${LEGACY_WPEWEBKIT_VERSION}"
export TARGET_WPE_SOURCE_DIR="${WORK}/wpewebkit-${TARGET_WPEWEBKIT_VERSION}"
export QT5_PLUGIN_SOURCE_DIR_DEFAULT="${BUILD_TOOLS}/qt5-plugin"

maybe_patch_glibc_versions() {
    [ "${PATCH_GLIBC_VERSIONS:-0}" = "1" ] || return 0
    python3 "${BUILD_TOOLS}/patch-glibc-versions.py" "$@"
}
