#!/bin/bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

echo ""
echo "--- [4] Building engine dependencies ---"

echo ""
echo "--- [5] Building libwpe ---"
if [ ! -f "${WPE_PREFIX}/lib/libwpe-1.0.so" ]; then
    cd "${WORK}"
    if [ ! -d libwpe ]; then
        git clone --depth=1 --branch "${LIBWPE_VERSION}" \
            https://github.com/WebPlatformForEmbedded/libwpe libwpe 2>/dev/null || \
        git clone --depth=1 https://github.com/WebPlatformForEmbedded/libwpe libwpe
    fi
    cd libwpe
    rm -rf build
    PKG_CONFIG_PATH="${WPE_PREFIX}/lib/pkgconfig" \
    meson setup build \
        --native-file "${BUILD_TOOLS}/native-meson.ini" \
        --prefix "${WPE_PREFIX}" \
        --libdir lib \
        --buildtype release \
        -Dlibxkbcommon:enable-x11=false \
        -Dlibxkbcommon:enable-wayland=false \
        -Dlibxkbcommon:enable-tools=false \
        -Dlibxkbcommon:enable-docs=false \
        -Dlibxkbcommon:enable-xkbregistry=false
    ninja -C build -j"${NPROC}" install
    echo "  libwpe installed."
else
    echo "  libwpe already built."
fi

echo ""
echo "--- [6] Building libepoxy ---"
if [ ! -f "${WPE_PREFIX}/lib/libepoxy.so" ]; then
    cd "${WORK}"
    if [ ! -d libepoxy ]; then
        git clone --depth=1 --branch "${LIBEPOXY_VERSION}" \
            https://github.com/anholt/libepoxy libepoxy 2>/dev/null || \
        git clone --depth=1 https://github.com/anholt/libepoxy libepoxy
    fi
    cd libepoxy
    apply_repo_patches 1 "${PWD}" "${ENGINE_SOURCE_PATCHES[@]}"
    rm -rf build
    PKG_CONFIG_PATH="${WPE_PREFIX}/lib/pkgconfig" \
    meson setup build \
        --native-file "${BUILD_TOOLS}/native-meson.ini" \
        --prefix "${WPE_PREFIX}" \
        --libdir lib \
        --buildtype release \
        -Dx11=false -Dglx=no -Degl=yes
    ninja -C build -j"${NPROC}" install
    echo "  libepoxy installed."
else
    echo "  libepoxy already built."
fi

echo ""
echo "--- [7] Building WPEBackend-fdo ---"
if [ ! -f "${WPE_PREFIX}/lib/libWPEBackend-fdo-1.0.so" ]; then
    cd "${WORK}"
    if [ ! -d WPEBackend-fdo ]; then
        git clone --depth=1 --branch "${WPEBACKEND_FDO_VERSION}" \
            https://github.com/igalia/WPEBackend-fdo WPEBackend-fdo 2>/dev/null || \
        git clone --depth=1 https://github.com/igalia/WPEBackend-fdo WPEBackend-fdo
    fi
    cd WPEBackend-fdo
    rm -rf build
    PKG_CONFIG_PATH="${WPE_PREFIX}/lib/pkgconfig" \
    meson setup build \
        --native-file "${BUILD_TOOLS}/native-meson.ini" \
        --prefix "${WPE_PREFIX}" \
        --libdir lib \
        --buildtype release
    ninja -C build -j"${NPROC}" install
    echo "  WPEBackend-fdo installed."
else
    echo "  WPEBackend-fdo already built."
fi
