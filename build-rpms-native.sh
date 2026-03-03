#!/bin/bash
# build-rpms-native.sh — Build all WPE SFOS RPMs using fpm (no sfdk required).
#
# Prerequisite: everything already built and installed under /opt/wpe-sfos/
# by the test build, plus browser binaries in sailfish-browser-wpe/build_*.
#
# Usage: bash build-rpms-native.sh
# Output RPMs are placed in /tmp/wpe-sfos-rpms/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BROWSER_SRC="/release/workspace/sailfish-browser-wpe"
WPE_PREFIX="/opt/wpe-sfos"
OUT="/tmp/wpe-sfos-rpms"
STAGING="/tmp/wpe-sfos-stage"

mkdir -p "$OUT"

# ---------------------------------------------------------------------------
# Helper: copy a file/symlink tree into staging root
# ---------------------------------------------------------------------------
stage_cp() {
    local src="$1" dst_dir="$2" root="$3"
    mkdir -p "${root}${dst_dir}"
    cp -a "$src" "${root}${dst_dir}/"
}

# ---------------------------------------------------------------------------
# Helper: build an RPM with fpm from a staging root
# ---------------------------------------------------------------------------
fpm_rpm() {
    local name="$1" version="$2" summary="$3" stage_root="$4"
    shift 4

    # Write ldconfig scripts
    local post="${STAGING}/post-${name}.sh" postun="${STAGING}/postun-${name}.sh"
    printf '#!/bin/sh\n/sbin/ldconfig || :\n' > "$post"
    printf '#!/bin/sh\n/sbin/ldconfig || :\n' > "$postun"

    echo "==> Building RPM: ${name}-${version}"
    fpm -s dir -t rpm \
        -n "$name" \
        -v "$version" \
        --iteration 1 \
        --architecture aarch64 \
        --rpm-summary "$summary" \
        --after-install "$post" \
        --after-remove "$postun" \
        --force \
        --package "${OUT}/${name}-${version}-1.aarch64.rpm" \
        "$@" \
        -C "$stage_root" .
    echo "    -> ${OUT}/${name}-${version}-1.aarch64.rpm"
}

# ===========================================================================
# 1. libwpe 1.17.0
# ===========================================================================
echo "--- Staging libwpe ---"
S="${STAGING}/libwpe"; rm -rf "$S"; mkdir -p "$S"
stage_cp "${WPE_PREFIX}/lib/libwpe-1.0.so.1.10.0"   /usr/lib64  "$S"
stage_cp "${WPE_PREFIX}/lib/libwpe-1.0.so.1"         /usr/lib64  "$S"
# devel files (include in same RPM for simplicity)
stage_cp "${WPE_PREFIX}/lib/libwpe-1.0.so"           /usr/lib64  "$S"
stage_cp "${WPE_PREFIX}/include/wpe-1.0"             /usr/include "$S"
mkdir -p "${S}/usr/lib64/pkgconfig"
cp -a "${WPE_PREFIX}/lib/pkgconfig/wpe-1.0.pc"      "${S}/usr/lib64/pkgconfig/"
sed -i "s|${WPE_PREFIX}|/usr|g"                      "${S}/usr/lib64/pkgconfig/wpe-1.0.pc"

fpm_rpm libwpe 1.17.0 "WPE platform library for Sailfish OS" "$S"

# ===========================================================================
# 2. libepoxy 1.5.11
# ===========================================================================
echo "--- Staging libepoxy ---"
S="${STAGING}/libepoxy"; rm -rf "$S"; mkdir -p "$S"
stage_cp "${WPE_PREFIX}/lib/libepoxy.so.0.0.0"       /usr/lib64  "$S"
stage_cp "${WPE_PREFIX}/lib/libepoxy.so.0"           /usr/lib64  "$S"
stage_cp "${WPE_PREFIX}/lib/libepoxy.so"             /usr/lib64  "$S"
stage_cp "${WPE_PREFIX}/include/epoxy"               /usr/include "$S"
mkdir -p "${S}/usr/lib64/pkgconfig"
cp -a "${WPE_PREFIX}/lib/pkgconfig/epoxy.pc"         "${S}/usr/lib64/pkgconfig/"
sed -i "s|${WPE_PREFIX}|/usr|g"                      "${S}/usr/lib64/pkgconfig/epoxy.pc"

fpm_rpm libepoxy 1.5.11 "OpenGL function pointer management for Sailfish OS" "$S"

# ===========================================================================
# 3. wpebackend-fdo 1.17.0
# ===========================================================================
echo "--- Staging wpebackend-fdo ---"
S="${STAGING}/wpebackend-fdo"; rm -rf "$S"; mkdir -p "$S"
cp -a "${WPE_PREFIX}/lib/libWPEBackend-fdo-1.0.so.1.11.0" /usr/lib64 "$S"  2>/dev/null; true
mkdir -p "${S}/usr/lib64"
cp -a "${WPE_PREFIX}/lib/libWPEBackend-fdo-1.0.so.1.11.0" "${S}/usr/lib64/"
ln -sfn libWPEBackend-fdo-1.0.so.1.11.0 "${S}/usr/lib64/libWPEBackend-fdo-1.0.so.1"
ln -sfn libWPEBackend-fdo-1.0.so.1      "${S}/usr/lib64/libWPEBackend-fdo-1.0.so"
cp -a "${WPE_PREFIX}/include/wpe-fdo-1.0"                 /usr/include "$S"
mkdir -p "${S}/usr/lib64/pkgconfig"
cp -a "${WPE_PREFIX}/lib/pkgconfig/wpebackend-fdo-1.0.pc"    "${S}/usr/lib64/pkgconfig/"
sed -i "s|${WPE_PREFIX}|/usr|g"                               "${S}/usr/lib64/pkgconfig/wpebackend-fdo-1.0.pc"

fpm_rpm wpebackend-fdo 1.17.0 "WPE backend (freedesktop.org/Wayland) for Sailfish OS" "$S" \
    --depends libwpe --depends libepoxy

# ===========================================================================
# 4. wpewebkit2 2.50.5
# ===========================================================================
echo "--- Staging wpewebkit2 ---"
S="${STAGING}/wpewebkit2"; rm -rf "$S"; mkdir -p "$S"

# Main library
stage_cp "${WPE_PREFIX}/lib/libWPEWebKit-2.0.so.1.6.10"    /usr/lib64 "$S"
stage_cp "${WPE_PREFIX}/lib/libWPEWebKit-2.0.so.1"         /usr/lib64 "$S"
stage_cp "${WPE_PREFIX}/lib/libWPEWebKit-2.0.so"           /usr/lib64 "$S"

# InjectedBundle (in both locations for safety)
mkdir -p "${S}/usr/lib64/wpe-webkit-2.0"
cp -a "${WPE_PREFIX}/lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so" \
      "${S}/usr/lib64/wpe-webkit-2.0/"

# Helper process binaries
mkdir -p "${S}/usr/libexec/wpe-webkit-2.0"
for helper in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
    cp -a "${WPE_PREFIX}/libexec/wpe-webkit-2.0/${helper}" \
          "${S}/usr/libexec/wpe-webkit-2.0/"
done

# Wrapper scripts for helper processes (set LD_PRELOAD, GStreamer paths, etc.)
mkdir -p "${S}/opt/wpe-sfos/libexec/wpe-webkit-2.0"
for helper in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
    cat > "${S}/opt/wpe-sfos/libexec/wpe-webkit-2.0/${helper}" << WRAPPER
#!/bin/sh
export LD_PRELOAD=/usr/lib64/wpe-compat/libglibc-compat.so:/usr/lib64/wpe-compat/libcow_string_compat.so:/usr/lib64/wpe-compat/libsigill_skip.so
export LD_LIBRARY_PATH=/usr/lib64/wpe-compat:/usr/lib64
export XDG_RUNTIME_DIR=/run/user/100000
export WAYLAND_DISPLAY=../../display/wayland-0
export GST_PLUGIN_SYSTEM_PATH_1_0=/usr/lib64/gstreamer-1.0
export GST_PLUGIN_PATH=/usr/lib64/gstreamer-1.0
export GST_PLUGIN_FEATURE_RANK=droidvdec:0,droidvenc:0
exec /usr/libexec/wpe-webkit-2.0/${helper} \$@
WRAPPER
    chmod 755 "${S}/opt/wpe-sfos/libexec/wpe-webkit-2.0/${helper}"
done

# Inspector resource (not MiniBrowser)
mkdir -p "${S}/usr/share/wpe-webkit-2.0"
cp -a "${WPE_PREFIX}/share/wpe-webkit-2.0/inspector.gresource" \
      "${S}/usr/share/wpe-webkit-2.0/"

# devel headers and pkg-config
stage_cp "${WPE_PREFIX}/include/wpe-webkit-2.0"            /usr/include "$S"
mkdir -p "${S}/usr/lib64/pkgconfig"
for pc in wpe-webkit-2.0.pc wpe-web-process-extension-2.0.pc; do
    cp -a "${WPE_PREFIX}/lib/pkgconfig/${pc}" "${S}/usr/lib64/pkgconfig/"
    sed -i "s|${WPE_PREFIX}|/usr|g"          "${S}/usr/lib64/pkgconfig/${pc}"
done

fpm_rpm wpewebkit2 2.50.5 "WPE WebKit 2.50.5 for Sailfish OS" "$S" \
    --depends libwpe --depends libepoxy --depends wpebackend-fdo

# ===========================================================================
# 5. wpewebkit2-qt5 2.50.5
# ===========================================================================
echo "--- Staging wpewebkit2-qt5 ---"
S="${STAGING}/wpewebkit2-qt5"; rm -rf "$S"; mkdir -p "$S"

# Patch glibc version symbols in libqtwpe.so before packaging
python3 "${SCRIPT_DIR}/patch-glibc-versions.py" \
    "${WPE_PREFIX}/lib/qt5/qml/org/wpewebkit/qtwpe/libqtwpe.so"
# Add libEGL.so.1 as DT_NEEDED (EGL symbols are directly referenced)
patchelf --add-needed libEGL.so.1 \
    "${WPE_PREFIX}/lib/qt5/qml/org/wpewebkit/qtwpe/libqtwpe.so" 2>/dev/null || true

mkdir -p "${S}/usr/lib64/qt5/qml/org/wpewebkit/qtwpe"
cp -a "${WPE_PREFIX}/lib/qt5/qml/org/wpewebkit/qtwpe/libqtwpe.so" \
      "${S}/usr/lib64/qt5/qml/org/wpewebkit/qtwpe/"
cp -a "${WPE_PREFIX}/lib/qt5/qml/org/wpewebkit/qtwpe/qmldir" \
      "${S}/usr/lib64/qt5/qml/org/wpewebkit/qtwpe/"
# Flat symlink so the browser binary can find libqtwpe.so via ldconfig
ln -sfn /usr/lib64/qt5/qml/org/wpewebkit/qtwpe/libqtwpe.so \
        "${S}/usr/lib64/libqtwpe.so"

fpm_rpm wpewebkit2-qt5 2.50.5 "WPE WebKit Qt5 QML plugin for Sailfish OS" "$S" \
    --depends wpewebkit2

# ===========================================================================
# 6. wpe-sfos-compat 1.0.0  (compiled from source)
# ===========================================================================
echo "--- Building wpe-sfos-compat shims ---"
COMPAT_SRC="${SCRIPT_DIR}"
COMPAT_BUILD="${STAGING}/compat-build"
rm -rf "$COMPAT_BUILD"; mkdir -p "$COMPAT_BUILD"

CC=gcc
CFLAGS="-O2 -march=armv8-a -fPIC -fvisibility=hidden"
SHARED="-shared -Wl,--allow-shlib-undefined"

for lib in \
    "libglibc-compat.so:libglibc-compat.c" \
    "libgetauxval_fix.so:libgetauxval_fix.c" \
    "libgetauxval_fix2.so:libgetauxval_fix2.c" \
    "libsigill_skip.so:libsigill_skip.c" \
    "libsigill_skip2.so:libsigill_skip2.c" \
    "libsigill_skip3.so:libsigill_skip3.c" \
    "libegl-stubs.so:libegl-stubs.c"
do
    name="${lib%%:*}"; src="${lib##*:}"
    $CC $CFLAGS $SHARED -o "${COMPAT_BUILD}/${name}" "${COMPAT_SRC}/${src}"
done
$CC $CFLAGS $SHARED -o "${COMPAT_BUILD}/libexecve_wrap.so"  "${COMPAT_SRC}/libexecve_wrap.c"  -ldl
$CC $CFLAGS $SHARED -o "${COMPAT_BUILD}/libexecve_wrap2.so" "${COMPAT_SRC}/libexecve_wrap2.c" -ldl

# Patch glibc version symbols in all compat shims (built with host glibc > 2.30)
for f in "${COMPAT_BUILD}"/*.so; do
    python3 "${SCRIPT_DIR}/patch-glibc-versions.py" "$f"
done

echo "--- Staging wpe-sfos-compat ---"
S="${STAGING}/wpe-sfos-compat"; rm -rf "$S"; mkdir -p "$S"
mkdir -p "${S}/usr/lib64/wpe-compat"
for so in "${COMPAT_BUILD}"/*.so; do
    cp -a "$so" "${S}/usr/lib64/wpe-compat/"
done
# Prebuilt cow_string compat shim (extracted from libstdc++.a for __cow_string symbol)
cp -a "${SCRIPT_DIR}/prebuilt/libcow_string_compat.so" "${S}/usr/lib64/wpe-compat/"

# Environment file — sets LD_PRELOAD for all nemo/user sessions
mkdir -p "${S}/var/lib/environment/nemo"
cat > "${S}/var/lib/environment/nemo/70-wpe-compat.conf" << 'EOF'
# WPE SFOS compatibility shims — loaded for all nemo user sessions.
LD_PRELOAD=/usr/lib64/wpe-compat/libglibc-compat.so:/usr/lib64/wpe-compat/libcow_string_compat.so:/usr/lib64/wpe-compat/libsigill_skip.so
EOF

fpm_rpm wpe-sfos-compat 1.0.0 "SFOS compatibility shims for WPE WebKit" "$S"

# ===========================================================================
# 7. atlantic-browser 1.0.0
# ===========================================================================
echo "--- Staging atlantic-browser ---"
S="${STAGING}/atlantic-browser"; rm -rf "$S"; mkdir -p "$S"

# Binary
mkdir -p "${S}/usr/bin"
cp -a "${BROWSER_SRC}/build_browser/atlantic-browser" "${S}/usr/bin/"

# WPE launcher wrapper script
cat > "${S}/usr/bin/atlantic-browser" << 'LAUNCHER'
#!/bin/sh
export LD_PRELOAD=/usr/lib64/wpe-compat/libglibc-compat.so:/usr/lib64/wpe-compat/libcow_string_compat.so:/usr/lib64/wpe-compat/libsigill_skip.so
export LD_LIBRARY_PATH=/usr/lib64/wpe-compat:/usr/lib64
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
export QT_QPA_PLATFORM=wayland
export XDG_RUNTIME_DIR=/run/user/100000
export WAYLAND_DISPLAY=../../display/wayland-0
export GST_PLUGIN_SYSTEM_PATH_1_0=/usr/lib64/gstreamer-1.0
export GST_PLUGIN_PATH=/usr/lib64/gstreamer-1.0
export WEBKIT_GST_ENABLE_HLS_SUPPORT=1
# Disable droid hardware decoders (crash via binder IPC) - use software libav/vpx instead
export GST_PLUGIN_FEATURE_RANK=droidvdec:0,droidvenc:0
exec /usr/bin/atlantic-browser.bin "$@"
LAUNCHER
chmod 755 "${S}/usr/bin/atlantic-browser"
# Move actual binary to .bin so wrapper takes the main name
mv "${S}/usr/bin/atlantic-browser" "${S}/usr/bin/atlantic-browser.launcher"
cp -a "${BROWSER_SRC}/build_browser/atlantic-browser" "${S}/usr/bin/atlantic-browser.bin"
mv "${S}/usr/bin/atlantic-browser.launcher" "${S}/usr/bin/atlantic-browser"

# libatlanticbrowser (versioned + symlinks)
mkdir -p "${S}/usr/lib64"
cp -a "${BROWSER_SRC}/build_wpe/libatlanticbrowser.so.1.0.0" "${S}/usr/lib64/"
ln -sfn libatlanticbrowser.so.1.0.0 "${S}/usr/lib64/libatlanticbrowser.so.1.0"
ln -sfn libatlanticbrowser.so.1.0.0 "${S}/usr/lib64/libatlanticbrowser.so.1"
ln -sfn libatlanticbrowser.so.1.0.0 "${S}/usr/lib64/libatlanticbrowser.so"

# QML files
mkdir -p "${S}/usr/share/atlantic-browser"
cp -a "${BROWSER_SRC}/apps/browser/qml/browser.qml" "${S}/usr/share/atlantic-browser/"
cp -a "${BROWSER_SRC}/apps/browser/qml/pages"        "${S}/usr/share/atlantic-browser/"
cp -a "${BROWSER_SRC}/apps/browser/qml/cover"        "${S}/usr/share/atlantic-browser/"
mkdir -p "${S}/usr/share/atlantic-browser/shared"
cp -a "${BROWSER_SRC}/apps/shared/"*.qml             "${S}/usr/share/atlantic-browser/shared/"

# Data files
mkdir -p "${S}/usr/share/atlantic-browser/data"
cp -a "${BROWSER_SRC}/data/prefs.js"                 "${S}/usr/share/atlantic-browser/data/"
cp -a "${BROWSER_SRC}/data/ua-update.json"           "${S}/usr/share/atlantic-browser/data/"

# Desktop file
mkdir -p "${S}/usr/share/applications"
cat > "${S}/usr/share/applications/atlantic-browser.desktop" << 'DESKTOP'
[Desktop Entry]
Type=Application
Name=Atlantic
Icon=icon-launcher-browser
Exec=/usr/bin/atlantic-browser %U
Comment=Atlantic Browser (WPE WebKit)
MimeType=text/html;application/xhtml+xml;application/xml;text/xml;x-scheme-handler/http;x-scheme-handler/https;
X-Maemo-Service=org.atlantic.browser.ui
X-Maemo-Object-Path=/ui
X-Maemo-Method=org.atlantic.browser.ui.openUrl
DESKTOP

# DBus service files
mkdir -p "${S}/usr/share/dbus-1/services"
cat > "${S}/usr/share/dbus-1/services/org.atlantic.browser.service" << 'DBUS'
[D-BUS Service]
Name=org.atlantic.browser
Exec=/usr/bin/atlantic-browser
DBUS
cat > "${S}/usr/share/dbus-1/services/org.atlantic.browser.ui.service" << 'DBUS'
[D-BUS Service]
Name=org.atlantic.browser.ui
Exec=/usr/bin/atlantic-browser
DBUS

# Translation
mkdir -p "${S}/usr/share/translations"
cp -a "${BROWSER_SRC}/build_browser/atlantic-browser_eng_en.qm" "${S}/usr/share/translations/"

# Sailjail profile
mkdir -p "${S}/etc/sailjail/applications"
cat > "${S}/etc/sailjail/applications/atlantic-browser.profile" << 'EOF'
[sailfish]
Sandboxing=disabled

[X-Sailjail]
Permissions=Internet;Audio
OrganizationName=org.atlantic
ApplicationName=atlantic-browser
EOF

fpm_rpm atlantic-browser 1.0.0 "Atlantic Browser (WPE WebKit engine)" "$S" \
    --depends wpewebkit2 \
    --depends wpewebkit2-qt5 \
    --depends wpe-sfos-compat

# ===========================================================================
echo ""
echo "All RPMs built successfully:"
ls -lh "$OUT"/*.rpm
