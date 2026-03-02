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
stage_cp "${WPE_PREFIX}/lib/libWPEBackend-fdo-1.0.so.1.11.0" /usr/lib64 "$S"
stage_cp "${WPE_PREFIX}/lib/libWPEBackend-fdo-1.0.so.1"      /usr/lib64 "$S"
stage_cp "${WPE_PREFIX}/lib/libWPEBackend-fdo-1.0.so"        /usr/lib64 "$S"
stage_cp "${WPE_PREFIX}/include/wpe-fdo-1.0"                 /usr/include "$S"
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

# Helper processes
mkdir -p "${S}/usr/libexec/wpe-webkit-2.0"
for helper in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
    cp -a "${WPE_PREFIX}/libexec/wpe-webkit-2.0/${helper}" \
          "${S}/usr/libexec/wpe-webkit-2.0/"
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

mkdir -p "${S}/usr/lib64/qt5/qml/org/wpewebkit/qtwpe"
cp -a "${WPE_PREFIX}/lib/qt5/qml/org/wpewebkit/qtwpe/libqtwpe.so" \
      "${S}/usr/lib64/qt5/qml/org/wpewebkit/qtwpe/"
cp -a "${WPE_PREFIX}/lib/qt5/qml/org/wpewebkit/qtwpe/qmldir" \
      "${S}/usr/lib64/qt5/qml/org/wpewebkit/qtwpe/"

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

echo "--- Staging wpe-sfos-compat ---"
S="${STAGING}/wpe-sfos-compat"; rm -rf "$S"; mkdir -p "$S"
mkdir -p "${S}/usr/lib64/wpe-compat"
for so in "${COMPAT_BUILD}"/*.so; do
    cp -a "$so" "${S}/usr/lib64/wpe-compat/"
done

# Environment file — sets LD_PRELOAD for all nemo/user sessions
mkdir -p "${S}/var/lib/environment/nemo"
cat > "${S}/var/lib/environment/nemo/70-wpe-compat.conf" << 'EOF'
# WPE SFOS compatibility shims — loaded for all nemo user sessions.
# Order: glibc-compat first, then getauxval, then sigill, then egl stubs.
LD_PRELOAD=/usr/lib64/wpe-compat/libglibc-compat.so:/usr/lib64/wpe-compat/libgetauxval_fix.so:/usr/lib64/wpe-compat/libsigill_skip.so:/usr/lib64/wpe-compat/libegl-stubs.so
EOF

fpm_rpm wpe-sfos-compat 1.0.0 "SFOS compatibility shims for WPE WebKit" "$S"

# ===========================================================================
# 7. sailfish-browser 2.3.30
# ===========================================================================
echo "--- Staging sailfish-browser ---"
S="${STAGING}/sailfish-browser"; rm -rf "$S"; mkdir -p "$S"

# Binary
mkdir -p "${S}/usr/bin"
cp -a "${BROWSER_SRC}/build_browser/sailfish-browser" "${S}/usr/bin/"

# libsailfishbrowser (versioned + symlinks)
mkdir -p "${S}/usr/lib64"
cp -a "${BROWSER_SRC}/build_wpe/libsailfishbrowser.so.1.0.0" "${S}/usr/lib64/"
ln -sfn libsailfishbrowser.so.1.0.0 "${S}/usr/lib64/libsailfishbrowser.so.1.0"
ln -sfn libsailfishbrowser.so.1.0.0 "${S}/usr/lib64/libsailfishbrowser.so.1"
ln -sfn libsailfishbrowser.so.1.0.0 "${S}/usr/lib64/libsailfishbrowser.so"

# QML files
mkdir -p "${S}/usr/share/sailfish-browser"
cp -a "${BROWSER_SRC}/apps/browser/qml/browser.qml" "${S}/usr/share/sailfish-browser/"
cp -a "${BROWSER_SRC}/apps/browser/qml/pages"        "${S}/usr/share/sailfish-browser/"
cp -a "${BROWSER_SRC}/apps/browser/qml/cover"        "${S}/usr/share/sailfish-browser/"
mkdir -p "${S}/usr/share/sailfish-browser/shared"
cp -a "${BROWSER_SRC}/apps/shared/"*.qml             "${S}/usr/share/sailfish-browser/shared/"

# Data files
mkdir -p "${S}/usr/share/sailfish-browser/data"
cp -a "${BROWSER_SRC}/data/prefs.js"                 "${S}/usr/share/sailfish-browser/data/"
cp -a "${BROWSER_SRC}/data/ua-update.json"           "${S}/usr/share/sailfish-browser/data/"

# Desktop files
mkdir -p "${S}/usr/share/applications"
cp -a "${BROWSER_SRC}/sailfish-browser.desktop"      "${S}/usr/share/applications/"
cp -a "${BROWSER_SRC}/sailfish-captiveportal.desktop" "${S}/usr/share/applications/"

# DBus service files
mkdir -p "${S}/usr/share/dbus-1/services"
cp -a "${BROWSER_SRC}/org.sailfishos.browser.service"    "${S}/usr/share/dbus-1/services/"
cp -a "${BROWSER_SRC}/org.sailfishos.browser.ui.service" "${S}/usr/share/dbus-1/services/"
cp -a "${BROWSER_SRC}/org.sailfishos.captiveportal.service" "${S}/usr/share/dbus-1/services/"

# Translation
mkdir -p "${S}/usr/share/translations"
cp -a "${BROWSER_SRC}/build_browser/sailfish-browser_eng_en.qm" "${S}/usr/share/translations/"

# Oneshot scripts
mkdir -p "${S}/usr/lib/oneshot.d"
cp -a "${BROWSER_SRC}/oneshot.d/browser-update-default-data"    "${S}/usr/lib/oneshot.d/"
cp -a "${BROWSER_SRC}/oneshot.d/browser-cleanup-startup-cache"  "${S}/usr/lib/oneshot.d/"
chmod +x "${S}/usr/lib/oneshot.d/"*

# Systemd user session drop-in
mkdir -p "${S}/usr/lib/systemd/user/user-session.target.d"
cp -a "${BROWSER_SRC}/50-sailfish-browser.conf" \
      "${S}/usr/lib/systemd/user/user-session.target.d/"

# Environment file
mkdir -p "${S}/var/lib/environment/nemo"
cp -a "${BROWSER_SRC}/data/70-browser.conf" "${S}/var/lib/environment/nemo/"

# Sailjail profile
mkdir -p "${S}/etc/sailjail/applications"
cat > "${S}/etc/sailjail/applications/sailfish-browser.profile" << 'EOF'
[sailfish]
Sandboxing=disabled

[X-Sailjail]
Permissions=Internet;Audio
OrganizationName=org.sailfishos
ApplicationName=sailfish-browser
EOF

fpm_rpm sailfish-browser 2.3.30 "Sailfish Browser (WPE WebKit engine)" "$S" \
    --depends wpewebkit2 \
    --depends wpewebkit2-qt5 \
    --depends wpe-sfos-compat \
    --depends "sailfishsilica-qt5 >= 1.2.33"

# ===========================================================================
echo ""
echo "All RPMs built successfully:"
ls -lh "$OUT"/*.rpm
