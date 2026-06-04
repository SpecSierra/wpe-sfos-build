#!/bin/bash
set -euo pipefail

# build-sandbox-deps.sh — build the device-side executables the WPE bubblewrap
# sandbox exec's at runtime: bwrap (bubblewrap) and xdg-dbus-proxy.
#
# These are the binaries baked into libWPEWebKit as BWRAP_EXECUTABLE /
# DBUS_PROXY_EXECUTABLE (see scripts/build-webkit.sh).  They are built NATIVE
# (aarch64-on-aarch64) like the rest of the engine: the SFOS 5.1 runtime ships a
# newer glibc (2.41) / glib (2.86) / libcap than the Ubuntu 24.04 build host, so
# host-built binaries run forward-compatibly on-device, and the SFOS sysroot
# does not carry capability.h for a cross build anyway.
#
# Installed into ${WPE_PREFIX}/bin; build-rpms-native.sh stages them to /usr/bin.

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

build_meson_release() {
    # $1 src dir, then meson extra args
    local src_dir="$1"; shift
    cd "${src_dir}"
    rm -rf build
    CC="ccache gcc" CXX="ccache g++" \
    meson setup build \
        --native-file "${BUILD_TOOLS}/native-meson.ini" \
        --prefix "${WPE_PREFIX}" \
        --buildtype release \
        "$@"
    ninja -C build -j"${NPROC}" install
}

echo ""
echo "--- Building sandbox runtime deps (bwrap, xdg-dbus-proxy) ---"

# ── bwrap (bubblewrap) ───────────────────────────────────────────────────────
_bwrap_stamp="${WPE_PREFIX}/bin/.bwrap-version"
if [ ! -x "${WPE_PREFIX}/bin/bwrap" ] || [ "$(cat "${_bwrap_stamp}" 2>/dev/null || true)" != "${BUBBLEWRAP_VERSION}" ]; then
    cd "${WORK}"
    if [ ! -d "bubblewrap-${BUBBLEWRAP_VERSION}" ]; then
        echo "  Downloading bubblewrap ${BUBBLEWRAP_VERSION}..."
        wget -q "https://github.com/containers/bubblewrap/releases/download/v${BUBBLEWRAP_VERSION}/bubblewrap-${BUBBLEWRAP_VERSION}.tar.xz" \
            -O "/tmp/bubblewrap-${BUBBLEWRAP_VERSION}.tar.xz"
        tar -xf "/tmp/bubblewrap-${BUBBLEWRAP_VERSION}.tar.xz" -C "${WORK}"
        rm -f "/tmp/bubblewrap-${BUBBLEWRAP_VERSION}.tar.xz"
    fi
    # No man/completions/tests; require_userns left false (we do not install setuid).
    build_meson_release "${WORK}/bubblewrap-${BUBBLEWRAP_VERSION}" \
        -Dman=disabled -Dselinux=disabled \
        -Dbash_completion=disabled -Dzsh_completion=disabled \
        -Dtests=false
    printf '%s\n' "${BUBBLEWRAP_VERSION}" > "${_bwrap_stamp}"
    echo "  bwrap installed: $("${WPE_PREFIX}/bin/bwrap" --version)"
else
    echo "  bwrap already built (${BUBBLEWRAP_VERSION})."
fi

# ── xdg-dbus-proxy ───────────────────────────────────────────────────────────
_xdp_stamp="${WPE_PREFIX}/bin/.xdg-dbus-proxy-version"
if [ ! -x "${WPE_PREFIX}/bin/xdg-dbus-proxy" ] || [ "$(cat "${_xdp_stamp}" 2>/dev/null || true)" != "${XDG_DBUS_PROXY_VERSION}" ]; then
    cd "${WORK}"
    if [ ! -d "xdg-dbus-proxy-${XDG_DBUS_PROXY_VERSION}" ]; then
        echo "  Downloading xdg-dbus-proxy ${XDG_DBUS_PROXY_VERSION}..."
        wget -q "https://github.com/flatpak/xdg-dbus-proxy/releases/download/${XDG_DBUS_PROXY_VERSION}/xdg-dbus-proxy-${XDG_DBUS_PROXY_VERSION}.tar.xz" \
            -O "/tmp/xdg-dbus-proxy-${XDG_DBUS_PROXY_VERSION}.tar.xz"
        tar -xf "/tmp/xdg-dbus-proxy-${XDG_DBUS_PROXY_VERSION}.tar.xz" -C "${WORK}"
        rm -f "/tmp/xdg-dbus-proxy-${XDG_DBUS_PROXY_VERSION}.tar.xz"
    fi
    build_meson_release "${WORK}/xdg-dbus-proxy-${XDG_DBUS_PROXY_VERSION}" \
        -Dman=disabled -Dtests=false
    printf '%s\n' "${XDG_DBUS_PROXY_VERSION}" > "${_xdp_stamp}"
    echo "  xdg-dbus-proxy installed: $("${WPE_PREFIX}/bin/xdg-dbus-proxy" --version)"
else
    echo "  xdg-dbus-proxy already built (${XDG_DBUS_PROXY_VERSION})."
fi
