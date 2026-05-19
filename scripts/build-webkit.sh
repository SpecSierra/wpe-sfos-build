#!/bin/bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

WPE_WEBKIT_VERSION="${WPE_WEBKIT_VERSION:-${LEGACY_WPEWEBKIT_VERSION}}"
WPE_SOURCE_DIR="${WPE_SOURCE_DIR:-${WORK}/wpewebkit-${WPE_WEBKIT_VERSION}}"
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

echo ""
echo "--- [8] Building WPEWebKit ${WPE_WEBKIT_VERSION} (expect 60-90 min) ---"
if [ ! -f "${WPE_PREFIX}/lib/libWPEWebKit-2.0.so" ]; then
    cd "${WORK}"
    if [ ! -d "${WPE_SOURCE_DIR}" ]; then
        echo "  Downloading tarball..."
        wget -q --show-progress \
            "https://wpewebkit.org/releases/wpewebkit-${WPE_WEBKIT_VERSION}.tar.xz" \
            -O "/tmp/wpewebkit-${WPE_WEBKIT_VERSION}.tar.xz"
        tar -xf "/tmp/wpewebkit-${WPE_WEBKIT_VERSION}.tar.xz"
        rm -f "/tmp/wpewebkit-${WPE_WEBKIT_VERSION}.tar.xz"
    fi

    cd "${WPE_SOURCE_DIR}"
    apply_repo_patches 1 "${PWD}" "${WEBKIT_SOURCE_PATCHES[@]}"

    PKG_CONFIG_PATH="${WPE_PREFIX}/lib/pkgconfig:${WPE_PREFIX}/lib/aarch64-linux-gnu/pkgconfig" \
    cmake -B WebKitBuild/Release -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${BUILD_TOOLS}/sfos-toolchain-native.cmake" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${WPE_PREFIX}" \
        -DICU_INCLUDE_DIR="${SYSROOT}/usr/include" \
        -DICU_INCLUDE_DIRS="${SYSROOT}/usr/include" \
        -DICU_UC_LIBRARY="${ICU_UC_LIB}" \
        -DICU_I18N_LIBRARY="${ICU_I18N_LIB}" \
        -DICU_DATA_LIBRARY="${ICU_DATA_LIB}" \
        -DICU_UC_LIBRARY_RELEASE="${ICU_UC_LIB}" \
        -DICU_I18N_LIBRARY_RELEASE="${ICU_I18N_LIB}" \
        -DICU_DATA_LIBRARY_RELEASE="${ICU_DATA_LIB}" \
        -DPORT=WPE \
        -DENABLE_VIDEO=OFF \
        -DENABLE_MEDIA_STREAM=OFF \
        -DENABLE_MEDIA_RECORDER=OFF \
        -DENABLE_WEB_CODECS=OFF \
        -DENABLE_WEB_AUDIO=OFF \
        -DENABLE_GEOLOCATION=OFF \
        -DENABLE_GAMEPAD=OFF \
        -DENABLE_SPELLCHECK=OFF \
        -DENABLE_SPEECH_SYNTHESIS=OFF \
        -DENABLE_SAMPLING_PROFILER=OFF \
        -DENABLE_INTROSPECTION=OFF \
        -DENABLE_WEBDRIVER=OFF \
        -DENABLE_XSLT=OFF \
        -DENABLE_BUBBLEWRAP_SANDBOX=OFF \
        -DENABLE_WPE_LEGACY_API=ON \
        -DUSE_ATK=OFF \
        -DUSE_GSTREAMER=OFF \
        -DUSE_GSTREAMER_GL=OFF \
        -DUSE_JPEGXL=OFF \
        -DUSE_LCMS=OFF \
        -DUSE_LIBBACKTRACE=OFF \
        -DUSE_LIBHYPHEN=OFF \
        -DUSE_OPENJPEG=OFF \
        -DUSE_WOFF2=OFF \
        -DUSE_AVIF=OFF \
        -DUSE_SYSTEM_SYSPROF_CAPTURE=NO

    ninja -C WebKitBuild/Release -j"${NPROC}"
    ninja -C WebKitBuild/Release install

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

    PKG_CONFIG_PATH="${WPE_PREFIX}/lib/pkgconfig:${WPE_PREFIX}/lib/aarch64-linux-gnu/pkgconfig" \
    cmake -B build -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="${BUILD_TOOLS}/sfos-toolchain.cmake" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${WPE_PREFIX}" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DWPE_WEBKIT_BUILD_DIR="${WPE_SOURCE_DIR}/WebKitBuild/Release"
    ninja -C build -j"${NPROC}" install
    echo "  Qt5 WPE plugin installed."
else
    echo "  Qt5 WPE plugin already built."
fi
