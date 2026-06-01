#!/bin/bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

WPE_WEBKIT_VERSION="${WPE_WEBKIT_VERSION:-${LEGACY_WPEWEBKIT_VERSION}}"
if [ -n "${WPE_SOURCE_DIR:-}" ]; then
    WPE_SOURCE_DIR="${WPE_SOURCE_DIR}"
elif [ -n "${CI_CACHE_ROOT:-}" ]; then
    WPE_SOURCE_DIR="${CI_CACHE_ROOT}/sources/wpewebkit-${WPE_WEBKIT_VERSION}"
elif [ -n "${CI_ROOT:-}" ]; then
    WPE_SOURCE_DIR="${CI_ROOT}/sources/wpewebkit-${WPE_WEBKIT_VERSION}"
else
    WPE_SOURCE_DIR="${WORK}/wpewebkit-${WPE_WEBKIT_VERSION}"
fi
QT5_PLUGIN_SOURCE_DIR="${QT5_PLUGIN_SOURCE_DIR:-${QT5_PLUGIN_SOURCE_DIR_DEFAULT}}"

resolve_sysroot_library() {
    local stem="$1"
    local direct="${SYSROOT}/usr/lib64/${stem}.so"
    local candidate

    if [ -e "${direct}" ]; then
        printf '%s\n' "${direct}"
        return 0
    fi

    for candidate in "${SYSROOT}/usr/lib64/${stem}.so".[0-9]*; do
        [ -e "${candidate}" ] || continue
        readlink -f "${candidate}"
        return 0
    done

    echo "ERROR: unable to resolve ${stem}.so under ${SYSROOT}/usr/lib64" >&2
    exit 1
}

ICU_UC_LIB="$(resolve_sysroot_library libicuuc)"
ICU_I18N_LIB="$(resolve_sysroot_library libicui18n)"
ICU_DATA_LIB="$(resolve_sysroot_library libicudata)"

stage_webkit_pkgconfig_files() {
    local build_dir="$1"
    local pc_file

    mkdir -p "${WPE_PREFIX}/lib/pkgconfig"
    for pc_file in wpe-webkit-2.0.pc wpe-web-process-extension-2.0.pc; do
        if [ -f "${build_dir}/${pc_file}" ]; then
            cp "${build_dir}/${pc_file}" "${WPE_PREFIX}/lib/pkgconfig/${pc_file}"
        fi
    done
}

install_webkit_build_metadata() {
    local build_dir="$1"
    local metadata_dir="${WPE_PREFIX}/share/wpe-webkit-2.0/build-config"
    local cache_path="${build_dir}/CMakeCache.txt"
    local config_path="${build_dir}/cmakeconfig.h"

    mkdir -p "${metadata_dir}"

    [ -f "${cache_path}" ] && cp "${cache_path}" "${metadata_dir}/CMakeCache.txt"
    [ -f "${config_path}" ] && cp "${config_path}" "${metadata_dir}/cmakeconfig.h"

    python3 "${BUILD_TOOLS}/scripts/write-webkit-feature-flags.py" \
        "${cache_path}" \
        "${metadata_dir}/feature-flags.txt" \
        "${WPE_WEBKIT_VERSION}" \
        --source-dir "${WPE_SOURCE_DIR}" \
        --build-dir "${build_dir}"
}

echo ""
echo "--- [8] Building WPEWebKit ${WPE_WEBKIT_VERSION} (expect 60-90 min) ---"
# Select compiler toolchain.  WEBKIT_COMPILER=clang uses Clang 18 + lld which
# enables ThinLTO via WebKit's own COMPILER_IS_CLANG guard in
# WebKitCompilerFlags.cmake (GCC LTO is explicitly disabled there because it
# dead-strips LLInt assembly symbols).  The default falls back to GCC.
WEBKIT_COMPILER="${WEBKIT_COMPILER:-gcc}"
if [ "${WEBKIT_COMPILER}" = "clang" ]; then
    WEBKIT_TOOLCHAIN_FILE="${BUILD_TOOLS}/sfos-toolchain-clang.cmake"
    echo "  Compiler: Clang 18 + lld (ThinLTO)"
    # ccache needs CCACHE_CPP2=1 to work correctly with Clang; without it
    # ccache re-preprocesses the source through the compiler preprocessor
    # and misses the cache on second runs.
    export CCACHE_CPP2=1
else
    WEBKIT_TOOLCHAIN_FILE="${BUILD_TOOLS}/sfos-toolchain-native.cmake"
    echo "  Compiler: GCC (no LTO)"
fi

if [ ! -f "${WPE_PREFIX}/lib/libWPEWebKit-2.0.so" ]; then
    webkit_source_parent="$(dirname "${WPE_SOURCE_DIR}")"
    mkdir -p "${webkit_source_parent}"

    cd "${webkit_source_parent}"
    if [ -n "${CI_CACHE_ROOT:-}" ] && [ -d "${WPE_SOURCE_DIR}" ]; then
        rm -rf "${WPE_SOURCE_DIR}"
    fi
    if [ ! -d "${WPE_SOURCE_DIR}" ]; then
        echo "  Downloading tarball..."
        wget -q --show-progress \
            "https://wpewebkit.org/releases/wpewebkit-${WPE_WEBKIT_VERSION}.tar.xz" \
            -O "/tmp/wpewebkit-${WPE_WEBKIT_VERSION}.tar.xz"
        tar -xf "/tmp/wpewebkit-${WPE_WEBKIT_VERSION}.tar.xz" -C "${webkit_source_parent}"
        rm -f "/tmp/wpewebkit-${WPE_WEBKIT_VERSION}.tar.xz"
    fi

    cd "${WPE_SOURCE_DIR}"
    apply_repo_patches 1 "${PWD}" "${WEBKIT_SOURCE_PATCHES[@]}"

    PKG_CONFIG_PATH="${WPE_PREFIX}/lib/pkgconfig:${WPE_PREFIX}/lib/aarch64-linux-gnu/pkgconfig" \
    cmake -B WebKitBuild/Release -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${WEBKIT_TOOLCHAIN_FILE}" \
        -DCMAKE_C_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${WPE_PREFIX}" \
        -C "${BUILD_TOOLS}/cmake/atlantic-wpe-features.cmake" \
        -DICU_INCLUDE_DIR="${SYSROOT}/usr/include" \
        -DICU_INCLUDE_DIRS="${SYSROOT}/usr/include" \
        -DICU_UC_LIBRARY="${ICU_UC_LIB}" \
        -DICU_I18N_LIBRARY="${ICU_I18N_LIB}" \
        -DICU_DATA_LIBRARY="${ICU_DATA_LIB}" \
        -DICU_UC_LIBRARY_RELEASE="${ICU_UC_LIB}" \
        -DICU_I18N_LIBRARY_RELEASE="${ICU_I18N_LIB}" \
        -DICU_DATA_LIBRARY_RELEASE="${ICU_DATA_LIB}" \
        -DPORT=WPE \
        -DENABLE_WPE_LEGACY_API=ON \
        -DUSE_JPEGXL=OFF

    ninja -C WebKitBuild/Release -j"${NPROC:-$(nproc)}"
    cmake --install WebKitBuild/Release --prefix "${WPE_PREFIX}"

    stage_webkit_pkgconfig_files "${WPE_SOURCE_DIR}/WebKitBuild/Release"
    install_webkit_build_metadata "${WPE_SOURCE_DIR}/WebKitBuild/Release"

    sed -i 's/libsoup-3\.0 //' "${WPE_PREFIX}/lib/pkgconfig/wpe-webkit-2.0.pc" 2>/dev/null || true

    ln -sf "${WPE_SOURCE_DIR}/WebKitBuild/Release/cmakeconfig.h" \
       "${WPE_SOURCE_DIR}/WebKitBuild/Release/config.h" 2>/dev/null || true

    mkdir -p "${WPE_PREFIX}/lib/wpe-webkit-2.0/injected-bundle"
    cp WebKitBuild/Release/lib/libWPEInjectedBundle.so \
       "${WPE_PREFIX}/lib/wpe-webkit-2.0/injected-bundle/" 2>/dev/null || \
    cp WebKitBuild/Release/lib/libWPEInjectedBundle.so "${WPE_PREFIX}/lib/" 2>/dev/null || true

    echo "  WPEWebKit installed."
else
    echo "  WPEWebKit already built."
    cmake --install "${WPE_SOURCE_DIR}/WebKitBuild/Release" --prefix "${WPE_PREFIX}"
    stage_webkit_pkgconfig_files "${WPE_SOURCE_DIR}/WebKitBuild/Release"
    install_webkit_build_metadata "${WPE_SOURCE_DIR}/WebKitBuild/Release"
fi

echo ""
if [ "${PATCH_GLIBC_VERSIONS}" = "1" ]; then
    echo "--- [9] Patching GLIBC version tags ---"
    for file in \
        "${WPE_PREFIX}"/lib/libWPEWebKit-2.0.so.*.*.* \
        "${WPE_PREFIX}/lib/libWPEInjectedBundle.so" \
        "${WPE_PREFIX}/lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so" \
        "${WPE_PREFIX}/libexec/wpe-webkit-2.0/WPEWebProcess" \
        "${WPE_PREFIX}/libexec/wpe-webkit-2.0/WPENetworkProcess" \
        "${WPE_PREFIX}/libexec/wpe-webkit-2.0/WPEGPUProcess"
    do
        [ -f "${file}" ] && maybe_patch_glibc_versions "${file}" || true
    done
else
    echo "--- [9] Skipping GLIBC version retagging for SFOS ${SFOS_SYSROOT_VERSION} ---"
fi

echo ""
echo "--- [10] Building Qt5 WPE plugin ---"
if [ ! -f "${WPE_PREFIX}/lib/qt5/qml/org/wpewebkit/qtwpe/libqtwpe.so" ]; then
    export PATH="${SYSROOT}/usr/lib64/qt5/bin:${PATH}"

    if [ ! -d "${WPE_SOURCE_DIR}/Source/WebKit/UIProcess/API/wpe/qt5" ]; then
        if [ ! -d "${QT5_PLUGIN_SOURCE_DIR}" ]; then
            echo "ERROR: ${QT5_PLUGIN_SOURCE_DIR} not found; required to copy the carried-forward Qt5 plugin into ${WPE_WEBKIT_VERSION}" >&2
            exit 1
        fi
        echo "  Copying Qt5 plugin from $(basename "${QT5_PLUGIN_SOURCE_DIR}")..."
        cp -a "${QT5_PLUGIN_SOURCE_DIR}/Source/WebKit/UIProcess/API/wpe/qt5" \
              "${WPE_SOURCE_DIR}/Source/WebKit/UIProcess/API/wpe/qt5"
    fi

    qt5_plugin_dir="${WPE_SOURCE_DIR}/Source/WebKit/UIProcess/API/wpe/qt5"
    apply_repo_patches 7 "${qt5_plugin_dir}" "${QT5_PLUGIN_PATCHES[@]}"
    cd "${qt5_plugin_dir}"

    rm -rf build

    PKG_CONFIG_PATH="${WPE_PREFIX}/lib/pkgconfig:${WPE_PREFIX}/lib/aarch64-linux-gnu/pkgconfig" \
    cmake -B build -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${BUILD_TOOLS}/sfos-toolchain.cmake" \
        -DCMAKE_C_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${WPE_PREFIX}" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DWPE_WEBKIT_BUILD_DIR="${WPE_SOURCE_DIR}/WebKitBuild/Release"
    ninja -C build -j"${NPROC:-$(nproc)}"
    cmake --install build --prefix "${WPE_PREFIX}"
    echo "  Qt5 WPE plugin installed."
else
    echo "  Qt5 WPE plugin already built."
fi
