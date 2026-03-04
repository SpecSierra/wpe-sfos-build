#!/bin/bash
# Master build script for WPE SFOS — native aarch64 Ubuntu 24.04
# Logs to /tmp/wpe-build.log
set -euo pipefail

LOG=/tmp/wpe-build.log
# Append all output to log file (caller redirects stdout/stderr here)


WORK=/release/workspace
BUILD_TOOLS="$WORK/wpe-sfos-build"
BROWSER_SRC="$WORK/sailfish-browser-wpe"
WPE_PREFIX=/opt/wpe-sfos
SYSROOT=/opt/sfos-sysroot
NPROC=$(nproc)

echo "================================================================"
echo "=== WPE SFOS Build started at $(date)"
echo "=== CPUs: $NPROC"
echo "================================================================"

# ---------------------------------------------------------------------------
# 0. Swap
# ---------------------------------------------------------------------------
echo ""
echo "--- [0] Setting up 64 GB swap ---"
if ! swapon --show | grep -q /swapfile; then
    fallocate -l 64G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "Swap activated: $(free -h | awk '/Swap/{print $2}')"
else
    echo "Swap already active"
fi

# ---------------------------------------------------------------------------
# 1. Install host build tools
# ---------------------------------------------------------------------------
echo ""
echo "--- [1] Installing build dependencies ---"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y \
    build-essential gcc g++ cmake ninja-build meson \
    pkg-config python3 python3-pip \
    git curl wget p7zip-full \
    patchelf bzip2 xz-utils \
    ruby ruby-dev rpm \
    libglib2.0-dev \
    libwayland-dev libxkbcommon-dev \
    libegl-dev libgles2-mesa-dev \
    libharfbuzz-dev libfontconfig1-dev libfreetype6-dev \
    libicu-dev libsqlite3-dev libxml2-dev libxslt1-dev \
    libpng-dev libjpeg-dev libwebp-dev zlib1g-dev \
    libdrm-dev libgbm-dev libcap-dev \
    libsoup-3.0-dev libsystemd-dev \
    libgcrypt20-dev libgpg-error-dev \
    libtasn1-6-dev \
    libwoff-dev libopenjp2-7-dev \
    liblcms2-dev libhyphen-dev \
    libcairo2-dev \
    libudev-dev libinput-dev \
    wayland-protocols \
    libmanette-0.2-dev \
    unifdef gperf flex bison perl \
    2>/dev/null

# fpm (used by build-rpms-native.sh to package RPMs)
gem list fpm | grep -q fpm || gem install --no-document fpm

echo "Build tools ready."

# ---------------------------------------------------------------------------
# 2. SFOS 5.0.0.62 sysroot
# ---------------------------------------------------------------------------
echo ""
echo "--- [2] Setting up SFOS 5.0.0.62 aarch64 sysroot ---"
if [ ! -d "$SYSROOT/usr/include" ]; then
    mkdir -p "$SYSROOT"
    SYSROOT_URL="https://releases.sailfishos.org/sdk/targets/Sailfish_OS-5.0.0.62-Sailfish_SDK_Target-aarch64.tar.7z"
    echo "  Downloading sysroot (177 MB)..."
    curl -L --progress-bar "$SYSROOT_URL" -o /tmp/sfos-sysroot.tar.7z
    echo "  Extracting..."
    # .tar.7z = 7z-compressed tar; pipe through tar
    cd "$SYSROOT"
    7z x /tmp/sfos-sysroot.tar.7z -so | tar -x --numeric-owner 2>/dev/null || \
        { 7z e /tmp/sfos-sysroot.tar.7z -o/tmp -y && \
          tar -xf /tmp/Sailfish_OS-5.0.0.62-Sailfish_SDK_Target-aarch64.tar -C "$SYSROOT" --numeric-owner; }
    rm -f /tmp/sfos-sysroot.tar.7z
    echo "  Sysroot ready."
else
    echo "  Sysroot already present."
fi

# ---------------------------------------------------------------------------
# 3. Clone source repos
# ---------------------------------------------------------------------------
echo ""
echo "--- [3] Cloning repositories ---"
mkdir -p "$WORK"

if [ ! -d "$BUILD_TOOLS/.git" ]; then
    git clone https://github.com/SpecSierra/wpe-sfos-build "$BUILD_TOOLS"
else
    echo "  wpe-sfos-build already cloned"
fi

if [ ! -d "$BROWSER_SRC/.git" ]; then
    git clone -b next https://github.com/SpecSierra/sailfish-browser "$BROWSER_SRC"
else
    echo "  sailfish-browser already cloned"
fi

# ---------------------------------------------------------------------------
# 4. Build prefix
# ---------------------------------------------------------------------------
mkdir -p "$WPE_PREFIX"

# ---------------------------------------------------------------------------
# 5. libwpe 1.17.0
# ---------------------------------------------------------------------------
echo ""
echo "--- [5] Building libwpe ---"
if [ ! -f "$WPE_PREFIX/lib/libwpe-1.0.so" ]; then
    cd "$WORK"
    if [ ! -d libwpe ]; then
        git clone --depth=1 --branch 1.17.0 \
            https://github.com/WebPlatformForEmbedded/libwpe libwpe 2>/dev/null || \
        git clone --depth=1 https://github.com/WebPlatformForEmbedded/libwpe libwpe
    fi
    cd libwpe
    rm -rf build
    PKG_CONFIG_PATH="$WPE_PREFIX/lib/pkgconfig" \
    meson setup build \
        --native-file "$BUILD_TOOLS/native-meson.ini" \
        --prefix "$WPE_PREFIX" \
        --buildtype release \
        -Dlibxkbcommon:enable-x11=false \
        -Dlibxkbcommon:enable-wayland=false \
        -Dlibxkbcommon:enable-tools=false \
        -Dlibxkbcommon:enable-docs=false \
        -Dlibxkbcommon:enable-xkbregistry=false
    ninja -C build -j"$NPROC" install
    echo "  libwpe installed."
else
    echo "  libwpe already built."
fi

# ---------------------------------------------------------------------------
# 6. libepoxy 1.5.11
# ---------------------------------------------------------------------------
echo ""
echo "--- [6] Building libepoxy ---"
if [ ! -f "$WPE_PREFIX/lib/libepoxy.so" ]; then
    cd "$WORK"
    if [ ! -d libepoxy ]; then
        git clone --depth=1 --branch 1.5.11 \
            https://github.com/anholt/libepoxy libepoxy 2>/dev/null || \
        git clone --depth=1 https://github.com/anholt/libepoxy libepoxy
    fi
    cd libepoxy
    # Apply SFOS compat patch: RTLD_DEFAULT fallback for missing EGL 1.5 symbols
    patch -p1 --forward < "$BUILD_TOOLS/libepoxy-rtld-default-fallback.patch" || true
    rm -rf build
    PKG_CONFIG_PATH="$WPE_PREFIX/lib/pkgconfig" \
    meson setup build \
        --native-file "$BUILD_TOOLS/native-meson.ini" \
        --prefix "$WPE_PREFIX" \
        --buildtype release \
        -Dx11=false -Dglx=no -Degl=yes
    ninja -C build -j"$NPROC" install
    echo "  libepoxy installed."
else
    echo "  libepoxy already built."
fi

# ---------------------------------------------------------------------------
# 7. WPEBackend-fdo 1.17.0
# ---------------------------------------------------------------------------
echo ""
echo "--- [7] Building WPEBackend-fdo ---"
if [ ! -f "$WPE_PREFIX/lib/libWPEBackend-fdo-1.0.so" ]; then
    cd "$WORK"
    if [ ! -d WPEBackend-fdo ]; then
        git clone --depth=1 --branch 1.17.0 \
            https://github.com/igalia/WPEBackend-fdo WPEBackend-fdo 2>/dev/null || \
        git clone --depth=1 https://github.com/igalia/WPEBackend-fdo WPEBackend-fdo
    fi
    cd WPEBackend-fdo
    rm -rf build
    PKG_CONFIG_PATH="$WPE_PREFIX/lib/pkgconfig" \
    meson setup build \
        --native-file "$BUILD_TOOLS/native-meson.ini" \
        --prefix "$WPE_PREFIX" \
        --buildtype release
    ninja -C build -j"$NPROC" install
    echo "  WPEBackend-fdo installed."
else
    echo "  WPEBackend-fdo already built."
fi

# ---------------------------------------------------------------------------
# 8. WPEWebKit 2.50.5  (long step — 60-90 min)
# ---------------------------------------------------------------------------
echo ""
echo "--- [8] Building WPEWebKit 2.50.5 (expect 60-90 min) ---"
if [ ! -f "$WPE_PREFIX/lib/libWPEWebKit-2.0.so" ]; then
    cd "$WORK"
    if [ ! -d wpewebkit-2.50.5 ]; then
        echo "  Downloading tarball..."
        wget -q --show-progress \
            "https://wpewebkit.org/releases/wpewebkit-2.50.5.tar.xz" \
            -O /tmp/wpewebkit-2.50.5.tar.xz
        tar -xf /tmp/wpewebkit-2.50.5.tar.xz
        rm -f /tmp/wpewebkit-2.50.5.tar.xz
    fi
    cd wpewebkit-2.50.5

    patch -p1 --forward < "$BUILD_TOOLS/webkit-quirks-no-video.patch" || true

    PKG_CONFIG_PATH="$WPE_PREFIX/lib/pkgconfig:$WPE_PREFIX/lib/aarch64-linux-gnu/pkgconfig" \
    cmake -B WebKitBuild/Release -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$BUILD_TOOLS/sfos-toolchain-native.cmake" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$WPE_PREFIX" \
        -DICU_INCLUDE_DIR=/usr/include \
        -DICU_UC_LIBRARY_RELEASE=/opt/sfos-sysroot/usr/lib64/libicuuc.so \
        -DICU_I18N_LIBRARY_RELEASE=/opt/sfos-sysroot/usr/lib64/libicui18n.so \
        -DICU_DATA_LIBRARY_RELEASE=/opt/sfos-sysroot/usr/lib64/libicudata.so \
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
        -DUSE_SKIA=ON \
        -DUSE_SYSPROF_CAPTURE=ON \
        -DUSE_SYSTEM_SYSPROF_CAPTURE=NO

    ninja -C WebKitBuild/Release -j"$NPROC"
    ninja -C WebKitBuild/Release install

    # libWPEInjectedBundle.so is not installed by ninja install
    mkdir -p "$WPE_PREFIX/lib/wpe-webkit-2.0/injected-bundle"
    cp WebKitBuild/Release/lib/libWPEInjectedBundle.so \
       "$WPE_PREFIX/lib/wpe-webkit-2.0/injected-bundle/" 2>/dev/null || \
    cp WebKitBuild/Release/lib/libWPEInjectedBundle.so "$WPE_PREFIX/lib/" 2>/dev/null || true

    echo "  WPEWebKit installed."
else
    echo "  WPEWebKit already built."
fi

# ---------------------------------------------------------------------------
# 9. Patch GLIBC version tags (WPEWebKit binaries)
# ---------------------------------------------------------------------------
echo ""
echo "--- [9] Patching GLIBC version tags ---"
for f in \
    "$WPE_PREFIX"/lib/libWPEWebKit-2.0.so.*.*.* \
    "$WPE_PREFIX/lib/libWPEInjectedBundle.so" \
    "$WPE_PREFIX/lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so" \
    "$WPE_PREFIX/libexec/wpe-webkit-2.0/WPEWebProcess" \
    "$WPE_PREFIX/libexec/wpe-webkit-2.0/WPENetworkProcess" \
    "$WPE_PREFIX/libexec/wpe-webkit-2.0/WPEGPUProcess"
do
    [ -f "$f" ] && python3 "$BUILD_TOOLS/patch-glibc-versions.py" "$f" || true
done

# ---------------------------------------------------------------------------
# 10. Qt5 WPE plugin (libqtwpe.so)
# ---------------------------------------------------------------------------
echo ""
echo "--- [10] Building Qt5 WPE plugin ---"
if [ ! -f "$WPE_PREFIX/lib/qt5/qml/org/wpewebkit/qtwpe/libqtwpe.so" ]; then
    export PATH="$SYSROOT/usr/lib64/qt5/bin:$PATH"

    QT5_PLUGIN_DIR="$WORK/wpewebkit-2.50.5/Source/WebKit/UIProcess/API/wpe/qt5"
    cd "$QT5_PLUGIN_DIR"
    patch -p4 --forward < "$BUILD_TOOLS/qt5-plugin-gnuinstalldirs.patch" || true

    PKG_CONFIG_PATH="$WPE_PREFIX/lib/pkgconfig:$WPE_PREFIX/lib/aarch64-linux-gnu/pkgconfig" \
    cmake -B build -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$BUILD_TOOLS/sfos-toolchain.cmake" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$WPE_PREFIX" \
        -DCMAKE_INSTALL_LIBDIR=lib
    ninja -C build -j"$NPROC" install
    echo "  Qt5 WPE plugin installed."
else
    echo "  Qt5 WPE plugin already built."
fi

# ---------------------------------------------------------------------------
# 11. Qt symlinks (needed so host ld can find SFOS Qt at runtime for qmake)
# ---------------------------------------------------------------------------
echo ""
echo "--- [11] Setting up Qt5 symlinks ---"
ln -sfn "$SYSROOT/usr/share/qt5"   /usr/share/qt5   2>/dev/null || true
ln -sfn "$SYSROOT/usr/lib64/qt5"   /usr/lib64/qt5   2>/dev/null || true
ln -sfn "$SYSROOT/usr/include/qt5" /usr/include/qt5 2>/dev/null || true
for lib in libQt5Core.so.5 libQt5Xml.so.5 libicui18n.so.70 libicuuc.so.70 libicudata.so.70 libpcre16.so.0; do
    [ -f "$SYSROOT/usr/lib64/$lib" ] && \
        ln -sfn "$SYSROOT/usr/lib64/$lib" "/usr/lib/$lib" 2>/dev/null || true
done

# ---------------------------------------------------------------------------
# 12. Build sailfish-browser
# ---------------------------------------------------------------------------
echo ""
echo "--- [12] Building sailfish-browser (atlantic-browser) ---"
cd "$BROWSER_SRC"
mkdir -p build_browser build_wpe

export PATH="$SYSROOT/usr/lib64/qt5/bin:$PATH"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
export PKG_CONFIG_PATH="$SYSROOT/usr/lib64/pkgconfig:$WPE_PREFIX/lib/pkgconfig"

rm -rf build && mkdir build && cd build
qmake -spec "$SYSROOT/usr/share/qt5/mkspecs/linux-g++" \
    ../sailfish-browser.pro \
    "CONFIG+=release" \
    "QMAKE_CXX=g++ --sysroot=$SYSROOT" \
    "QMAKE_CC=gcc --sysroot=$SYSROOT" \
    "QMAKE_LINK=g++ --sysroot=$SYSROOT" \
    "WPE_SFOS_PREFIX=$WPE_PREFIX" \
    "SFOS_SYSROOT=$SYSROOT" \
    "WPE_SOURCE_DIR=$WORK/wpewebkit-2.50.5"

# captiveportal won't build (not ported to WPE), build only core + browser
make -C apps/lib   -j"$NPROC"
make -C apps/browser -j"$NPROC"

# Collect artifacts into locations expected by build-rpms-native.sh
cd "$BROWSER_SRC"
find build -name "atlantic-browser" -not -name "*.o" -type f \
    -exec cp {} build_browser/atlantic-browser \; 2>/dev/null || true
find build -name "libatlanticbrowser.so*" -type f \
    -exec cp {} build_wpe/ \; 2>/dev/null || true
find build -name "*.qm" -exec cp {} build_browser/ \; 2>/dev/null || true

echo "  sailfish-browser built."

# ---------------------------------------------------------------------------
# 13. Package RPMs
# ---------------------------------------------------------------------------
echo ""
echo "--- [13] Building RPMs ---"
bash "$BUILD_TOOLS/build-rpms-native.sh"

echo ""
echo "================================================================"
echo "=== Build COMPLETE at $(date)"
echo "=== RPMs in /tmp/wpe-sfos-rpms/:"
ls -lh /tmp/wpe-sfos-rpms/*.rpm
echo "================================================================"
