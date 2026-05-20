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
source "${SCRIPT_DIR}/scripts/common.sh"

OUT="${OUT:-/tmp/wpe-sfos-rpms}"
STAGING="${STAGING:-/tmp/wpe-sfos-stage}"
PACKAGE_RUNTIME_PREFIX="${PACKAGE_RUNTIME_PREFIX:-/opt/wpe-sfos}"

mkdir -p "$OUT"

# ---------------------------------------------------------------------------
# Helpers: compat flags and GLIBC retagging
# ---------------------------------------------------------------------------
maybe_patch_glibc_versions() {
    [ "${PATCH_GLIBC_VERSIONS}" = "1" ] || return 0
    python3 "${SCRIPT_DIR}/patch-glibc-versions.py" "$@"
}

build_ld_preload() {
    local libs=()

    [ "${USE_GLIBC_COMPAT}" = "1" ] && libs+=("/usr/lib64/wpe-compat/libglibc-compat.so")
    [ "${USE_COW_STRING_COMPAT}" = "1" ] && libs+=("/usr/lib64/wpe-compat/libcow_string_compat.so")
    [ "${USE_SIGILL_SKIP}" = "1" ] && libs+=("/usr/lib64/wpe-compat/libsigill_skip.so")
    [ "${USE_GLIB_COMPAT}" = "1" ] && libs+=("/usr/lib64/wpe-compat/libglib-compat.so")
    [ "${USE_EGL_STUBS}" = "1" ] && libs+=("/usr/lib64/wpe-compat/libegl-stubs.so")

    local IFS=:
    printf '%s' "${libs[*]}"
}

WPE_COMPAT_PRELOAD="$(build_ld_preload)"
WPE_COMPAT_LIBRARY_PATH="/usr/lib64/wpe-compat:/usr/lib64"
WPE_HELPER_LIBRARY_PATH="${WPE_COMPAT_LIBRARY_PATH}:${PACKAGE_RUNTIME_PREFIX}/lib"

if [ -n "${WPE_COMPAT_PRELOAD}" ]; then
    WPE_PRELOAD_EXPORT="export LD_PRELOAD=${WPE_COMPAT_PRELOAD}"
else
    WPE_PRELOAD_EXPORT=""
fi

# ---------------------------------------------------------------------------
# Helper: copy a file/symlink tree into staging root
# ---------------------------------------------------------------------------
stage_cp() {
    local src="$1" dst_dir="$2" root="$3"
    mkdir -p "${root}${dst_dir}"
    cp -a "$src" "${root}${dst_dir}/"
}

stage_shared_library_family() {
    local source_stem="$1" dst_dir="$2" root="$3"
    local matches=("${source_stem}"*)

    if [ ! -e "${matches[0]}" ]; then
        echo "ERROR: no shared-library files found for ${source_stem}" >&2
        return 1
    fi

    mkdir -p "${root}${dst_dir}"
    cp -a "${matches[@]}" "${root}${dst_dir}/"
}

patch_staged_library_family() {
    local staged_symlink="$1"
    maybe_patch_glibc_versions "$(readlink -f "${staged_symlink}")"
}

patch_binary_prefix_string() {
    local file="$1" old="$2" new="$3"
    python3 - "$file" "$old" "$new" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
old = sys.argv[2].encode()
new = sys.argv[3].encode()

if len(new) > len(old):
    raise SystemExit(f"replacement is longer than source: {new!r} > {old!r}")

data = path.read_bytes()
count = data.count(old)
if count == 0:
    raise SystemExit(f"source string not found in {path}: {sys.argv[2]}")

data = data.replace(old, new + b"\0" * (len(old) - len(new)))
path.write_bytes(data)
print(f"patched {count} occurrence(s) of {sys.argv[2]} in {path}")
PY
}

patch_webkit_runtime_paths() {
    local file="$1"
    patch_binary_prefix_string "$file" \
        "${WPE_PREFIX}/libexec/wpe-webkit-2.0" \
        "/usr/libexec/wpe-webkit-2.0"
    patch_binary_prefix_string "$file" \
        "${WPE_PREFIX}/share/locale" \
        "/usr/share/locale"
    patch_binary_prefix_string "$file" \
        "${WPE_PREFIX}/lib/wpe-webkit-2.0/injected-bundle/" \
        "${PACKAGE_RUNTIME_PREFIX}/lib/wpe-webkit-2.0/injected-bundle/"
    patch_binary_prefix_string "$file" \
        "${WPE_PREFIX}/share/wpe-webkit-2.0" \
        "/usr/share/wpe-webkit-2.0"
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
# 1. libwpe
# ===========================================================================
echo "--- Staging libwpe ---"
S="${STAGING}/libwpe"; rm -rf "$S"; mkdir -p "$S"
stage_shared_library_family "${WPE_PREFIX}/lib/libwpe-1.0.so" /usr/lib64 "$S"
# devel files (include in same RPM for simplicity)
stage_cp "${WPE_PREFIX}/include/wpe-1.0"             /usr/include "$S"
mkdir -p "${S}/usr/lib64/pkgconfig"
cp -a "${WPE_PREFIX}/lib/pkgconfig/wpe-1.0.pc"      "${S}/usr/lib64/pkgconfig/"
sed -i "s|${WPE_PREFIX}|/usr|g"                      "${S}/usr/lib64/pkgconfig/wpe-1.0.pc"

fpm_rpm libwpe "$LIBWPE_VERSION" "WPE platform library for Sailfish OS" "$S"

# ===========================================================================
# 2. libepoxy
# ===========================================================================
echo "--- Staging libepoxy ---"
S="${STAGING}/libepoxy"; rm -rf "$S"; mkdir -p "$S"
stage_shared_library_family "${WPE_PREFIX}/lib/libepoxy.so" /usr/lib64 "$S"
patch_staged_library_family "${S}/usr/lib64/libepoxy.so"
stage_cp "${WPE_PREFIX}/include/epoxy"               /usr/include "$S"
mkdir -p "${S}/usr/lib64/pkgconfig"
cp -a "${WPE_PREFIX}/lib/pkgconfig/epoxy.pc"         "${S}/usr/lib64/pkgconfig/"
sed -i "s|${WPE_PREFIX}|/usr|g"                      "${S}/usr/lib64/pkgconfig/epoxy.pc"

fpm_rpm libepoxy "$LIBEPOXY_VERSION" "OpenGL function pointer management for Sailfish OS" "$S"

# ===========================================================================
# 3. wpebackend-fdo
# ===========================================================================
echo "--- Staging wpebackend-fdo ---"
S="${STAGING}/wpebackend-fdo"; rm -rf "$S"; mkdir -p "$S"
stage_shared_library_family "${WPE_PREFIX}/lib/libWPEBackend-fdo-1.0.so" /usr/lib64 "$S"
patch_staged_library_family "${S}/usr/lib64/libWPEBackend-fdo-1.0.so"
stage_cp "${WPE_PREFIX}/include/wpe-fdo-1.0"              /usr/include "$S"
mkdir -p "${S}/usr/lib64/pkgconfig"
cp -a "${WPE_PREFIX}/lib/pkgconfig/wpebackend-fdo-1.0.pc"    "${S}/usr/lib64/pkgconfig/"
sed -i "s|${WPE_PREFIX}|/usr|g" "${S}/usr/lib64/pkgconfig/wpebackend-fdo-1.0.pc"

fpm_rpm wpebackend-fdo "$WPEBACKEND_FDO_VERSION" "WPE backend (freedesktop.org/Wayland) for Sailfish OS" "$S" \
    --depends libwpe --depends libepoxy

# ===========================================================================
# 4. wpewebkit2
# ===========================================================================
echo "--- Staging wpewebkit2 ---"
S="${STAGING}/wpewebkit2"; rm -rf "$S"; mkdir -p "$S"

# Main library — patch the staged copy rather than mutating the source prefix.
stage_shared_library_family "${WPE_PREFIX}/lib/libWPEWebKit-2.0.so" /usr/lib64 "$S"
patch_staged_library_family "${S}/usr/lib64/libWPEWebKit-2.0.so"
patch_webkit_runtime_paths "$(readlink -f "${S}/usr/lib64/libWPEWebKit-2.0.so")"

# InjectedBundle — staged in both the install path AND the compile-time prefix
# (WPEWebProcess binary has /opt/wpe-sfos hard-coded as the injected-bundle dir)
mkdir -p "${S}/usr/lib64/wpe-webkit-2.0"
mkdir -p "${S}${PACKAGE_RUNTIME_PREFIX}/lib/wpe-webkit-2.0/injected-bundle"
cp -a "${WPE_PREFIX}/lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so" \
      "${S}/usr/lib64/wpe-webkit-2.0/"
cp -a "${WPE_PREFIX}/lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so" \
      "${S}${PACKAGE_RUNTIME_PREFIX}/lib/wpe-webkit-2.0/injected-bundle/"

# Helper process binaries — patch GLIBC version requirements (2.34→2.17) so they run on SFOS
mkdir -p "${S}/usr/libexec/wpe-webkit-2.0"
for helper in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
    cp -a "${WPE_PREFIX}/libexec/wpe-webkit-2.0/${helper}" \
          "${S}/usr/libexec/wpe-webkit-2.0/"
    maybe_patch_glibc_versions "${S}/usr/libexec/wpe-webkit-2.0/${helper}"
done

# Wrapper scripts for helper processes (set LD_PRELOAD, GStreamer paths, etc.)
mkdir -p "${S}${PACKAGE_RUNTIME_PREFIX}/libexec/wpe-webkit-2.0"
for helper in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
    cat > "${S}${PACKAGE_RUNTIME_PREFIX}/libexec/wpe-webkit-2.0/${helper}" <<WRAPPER
#!/bin/sh
${WPE_PRELOAD_EXPORT}
export LD_LIBRARY_PATH=${WPE_HELPER_LIBRARY_PATH}
export XDG_RUNTIME_DIR=/run/user/100000
export WAYLAND_DISPLAY=../../display/wayland-0
export GST_PLUGIN_SYSTEM_PATH_1_0=/usr/lib64/gstreamer-1.0
export GST_PLUGIN_PATH=/usr/lib64/gstreamer-1.0
export GST_PLUGIN_FEATURE_RANK=droidvdec:0,droidvenc:0
exec /usr/libexec/wpe-webkit-2.0/${helper} \$@
WRAPPER
    chmod 755 "${S}${PACKAGE_RUNTIME_PREFIX}/libexec/wpe-webkit-2.0/${helper}"
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

fpm_rpm wpewebkit2 "$LEGACY_WPEWEBKIT_VERSION" "WPE WebKit ${LEGACY_WPEWEBKIT_VERSION} for Sailfish OS" "$S" \
    --depends libwpe --depends libepoxy --depends wpebackend-fdo

# ===========================================================================
# 5. wpewebkit2-qt5
# ===========================================================================
echo "--- Staging wpewebkit2-qt5 ---"
S="${STAGING}/wpewebkit2-qt5"; rm -rf "$S"; mkdir -p "$S"

mkdir -p "${S}/usr/lib64/qt5/qml/org/wpewebkit/qtwpe"
cp -a "${WPE_PREFIX}/lib/qt5/qml/org/wpewebkit/qtwpe/libqtwpe.so" \
      "${S}/usr/lib64/qt5/qml/org/wpewebkit/qtwpe/"
cp -a "${WPE_PREFIX}/lib/qt5/qml/org/wpewebkit/qtwpe/qmldir" \
      "${S}/usr/lib64/qt5/qml/org/wpewebkit/qtwpe/"
maybe_patch_glibc_versions "${S}/usr/lib64/qt5/qml/org/wpewebkit/qtwpe/libqtwpe.so"
if ! patchelf --print-needed "${S}/usr/lib64/qt5/qml/org/wpewebkit/qtwpe/libqtwpe.so" | grep -qx 'libEGL.so.1'; then
    patchelf --add-needed libEGL.so.1 \
        "${S}/usr/lib64/qt5/qml/org/wpewebkit/qtwpe/libqtwpe.so"
fi
# Flat symlink so the browser binary can find libqtwpe.so via ldconfig
ln -sfn /usr/lib64/qt5/qml/org/wpewebkit/qtwpe/libqtwpe.so \
        "${S}/usr/lib64/libqtwpe.so"

fpm_rpm wpewebkit2-qt5 "$LEGACY_WPEWEBKIT_VERSION" "WPE WebKit Qt5 QML plugin for Sailfish OS" "$S" \
    --depends wpewebkit2

# ===========================================================================
# 6. wpe-sfos-compat  (compiled from source)
# ===========================================================================
echo "--- Building wpe-sfos-compat shims ---"
COMPAT_SRC="${SCRIPT_DIR}"
COMPAT_BUILD="${STAGING}/compat-build"
rm -rf "$COMPAT_BUILD"; mkdir -p "$COMPAT_BUILD"

CC=gcc
CFLAGS="-O2 -march=armv8-a -fPIC -fvisibility=hidden"
SHARED="-shared -Wl,--allow-shlib-undefined"

for lib in \
    "libgetauxval_fix.so:libgetauxval_fix.c" \
    "libgetauxval_fix2.so:libgetauxval_fix2.c" \
    "libsigill_skip.so:libsigill_skip.c" \
    "libsigill_skip2.so:libsigill_skip2.c" \
    "libsigill_skip3.so:libsigill_skip3.c"
do
    name="${lib%%:*}"; src="${lib##*:}"
    $CC $CFLAGS $SHARED -o "${COMPAT_BUILD}/${name}" "${COMPAT_SRC}/${src}"
done

# libegl-stubs.so: must NOT use -fvisibility=hidden — symbols must be globally
# visible so dlsym(RTLD_DEFAULT, "eglCreateSync") finds them in patched libepoxy
$CC -O2 -march=armv8-a -fPIC $SHARED \
    -o "${COMPAT_BUILD}/libegl-stubs.so" "${COMPAT_SRC}/libegl-stubs.c"

# libglibc-compat.so: needs version script (GLIBC_2.17 + GLIBC_2.34 sections)
# and must export dlopen/dlsym/dlerror@GLIBC_2.34 for binaries built on glibc 2.34+
if [ "${USE_GLIBC_COMPAT}" = "1" ]; then
    $CC -O2 -march=armv8-a -fPIC $SHARED \
        -Wl,--version-script="${COMPAT_SRC}/libglibc-compat.map" \
        -o "${COMPAT_BUILD}/libglibc-compat.so" "${COMPAT_SRC}/libglibc-compat.c" \
        -ldl
fi

# GLib compat: provides g_once_init_enter/leave_pointer absent from Jolla's GLib 2.78.4 build
# Must link against SFOS libglib-2.0 so the wrappers call the real SFOS implementation
if [ "${USE_GLIB_COMPAT}" = "1" ]; then
    $CC -O2 -march=armv8-a -fPIC $SHARED \
        --sysroot="${SFOS_SYSROOT}" \
        -Wl,-soname,libglib-compat.so \
        -o "${COMPAT_BUILD}/libglib-compat.so" "${COMPAT_SRC}/libglib_compat.c" \
        -L"${SFOS_SYSROOT}/usr/lib64" -lglib-2.0
    ln -sfn libglib-compat.so "${COMPAT_BUILD}/libglib-compat-preload.so"
fi
$CC $CFLAGS $SHARED -o "${COMPAT_BUILD}/libexecve_wrap.so"  "${COMPAT_SRC}/libexecve_wrap.c"  -ldl
$CC $CFLAGS $SHARED -o "${COMPAT_BUILD}/libexecve_wrap2.so" "${COMPAT_SRC}/libexecve_wrap2.c" -ldl

# Stub: libgssapi_krb5.so.2 (GSSAPI for libsoup3 — always returns unavailable on SFOS)
# Note: must NOT use -fvisibility=hidden here — version-script requires GLOBAL symbols
$CC -O2 -march=armv8-a -fPIC $SHARED \
    -Wl,--version-script="${COMPAT_SRC}/libgssapi_krb5.map" \
    -Wl,-soname,libgssapi_krb5.so.2 \
    -o "${COMPAT_BUILD}/libgssapi_krb5.so.2" "${COMPAT_SRC}/libgssapi_krb5_stub.c"
ln -sfn libgssapi_krb5.so.2 "${COMPAT_BUILD}/libgssapi_krb5.so"

# Stub: libharfbuzz-icu.so.0 (avoids pulling in libicuuc.so.74 which SFOS doesn't have)
# Note: must NOT use -fvisibility=hidden here — symbols must be globally visible
$CC -O2 -march=armv8-a -fPIC $SHARED \
    -Wl,-soname,libharfbuzz-icu.so.0 \
    -o "${COMPAT_BUILD}/libharfbuzz-icu.so.0" "${COMPAT_SRC}/libharfbuzz_icu_stub.c"
ln -sfn libharfbuzz-icu.so.0 "${COMPAT_BUILD}/libharfbuzz-icu.so"

# Copy missing runtime libs from Ubuntu (not present on SFOS) into compat dir
UBUNTU_LIBS=/usr/lib/aarch64-linux-gnu
for lib in \
    libsoup-3.0.so.0.7.1 \
    libbrotlidec.so.1.1.0 \
    libbrotlicommon.so.1.1.0 \
    libatomic.so.1.2.0 \
    libjpeg.so.8.2.2 \
    libgbm.so.1.0.0; do
    cp "${UBUNTU_LIBS}/${lib}" "${COMPAT_BUILD}/${lib}"
done

# Patch glibc version symbols in all compat shims and bundled libs
if [ "${PATCH_GLIBC_VERSIONS}" = "1" ]; then
    for f in "${COMPAT_BUILD}"/*.so "${COMPAT_BUILD}"/*.so.[0-9]*; do
        [ -f "$f" ] && maybe_patch_glibc_versions "$f"
    done
fi

echo "--- Staging wpe-sfos-compat ---"
S="${STAGING}/wpe-sfos-compat"; rm -rf "$S"; mkdir -p "$S"
mkdir -p "${S}/usr/lib64/wpe-compat"
# Copy all compat shims
for so in "${COMPAT_BUILD}"/*.so "${COMPAT_BUILD}"/*.so.[0-9]*; do
    [ -f "$so" ] && cp -a "$so" "${S}/usr/lib64/wpe-compat/"
done
# Prebuilt cow_string compat shim (extracted from libstdc++.a for __cow_string symbol)
if [ "${USE_COW_STRING_COMPAT}" = "1" ]; then
    cp -a "${SCRIPT_DIR}/prebuilt/libcow_string_compat.so" "${S}/usr/lib64/wpe-compat/"
fi

# Create versioned symlinks for bundled runtime libs
(cd "${S}/usr/lib64/wpe-compat"
    ln -sfn libsoup-3.0.so.0.7.1    libsoup-3.0.so.0
    ln -sfn libsoup-3.0.so.0.7.1    libsoup-3.0.so
    ln -sfn libbrotlidec.so.1.1.0   libbrotlidec.so.1
    ln -sfn libbrotlicommon.so.1.1.0 libbrotlicommon.so.1
    ln -sfn libatomic.so.1.2.0      libatomic.so.1
    ln -sfn libjpeg.so.8.2.2        libjpeg.so.8
    ln -sfn libgbm.so.1.0.0         libgbm.so.1
)

# Environment file — sets LD_PRELOAD and LD_LIBRARY_PATH for all nemo/user sessions
mkdir -p "${S}/var/lib/environment/nemo"
cat > "${S}/var/lib/environment/nemo/70-wpe-compat.conf" <<EOF
# WPE SFOS compatibility shims — loaded for all nemo user sessions.
EOF
if [ -n "${WPE_COMPAT_PRELOAD}" ]; then
    printf 'LD_PRELOAD=%s\n' "${WPE_COMPAT_PRELOAD}" >> "${S}/var/lib/environment/nemo/70-wpe-compat.conf"
fi
printf 'LD_LIBRARY_PATH=%s\n' "${WPE_COMPAT_LIBRARY_PATH}" >> "${S}/var/lib/environment/nemo/70-wpe-compat.conf"

fpm_rpm wpe-sfos-compat "$WPE_SFOS_COMPAT_VERSION" "SFOS compatibility shims for WPE WebKit" "$S"

# ===========================================================================
# 7. atlantic-browser
# ===========================================================================
echo "--- Staging atlantic-browser ---"
S="${STAGING}/atlantic-browser"; rm -rf "$S"; mkdir -p "$S"

# Binary
mkdir -p "${S}/usr/bin"
cp -a "${BROWSER_SRC}/build_browser/atlantic-browser" "${S}/usr/bin/"

# WPE launcher environment wrapper
cat > "${S}/usr/bin/atlantic-browser-env" <<LAUNCHER
#!/bin/sh
${WPE_PRELOAD_EXPORT}
export LD_LIBRARY_PATH=${WPE_HELPER_LIBRARY_PATH}
export QT_QPA_PLATFORM=wayland
export XDG_RUNTIME_DIR=/run/user/100000
export WAYLAND_DISPLAY=../../display/wayland-0
export ATLANTIC_BROWSER_RUNTIME_DELAY_MS=2000
export GST_PLUGIN_SYSTEM_PATH_1_0=/usr/lib64/gstreamer-1.0
export GST_PLUGIN_PATH=/usr/lib64/gstreamer-1.0
export WEBKIT_GST_ENABLE_HLS_SUPPORT=1
# Disable droid hardware decoders (crash via binder IPC) - use software libav/vpx instead
export GST_PLUGIN_FEATURE_RANK=droidvdec:0,droidvenc:0
exec /usr/bin/atlantic-browser.bin "\$@"
LAUNCHER
chmod 755 "${S}/usr/bin/atlantic-browser-env"

# WPE launcher wrapper script
cat > "${S}/usr/bin/atlantic-browser" <<LAUNCHER
#!/bin/sh
exec /usr/bin/atlantic-browser-env "\$@"
LAUNCHER
chmod 755 "${S}/usr/bin/atlantic-browser"
cp -a "${BROWSER_SRC}/build_browser/atlantic-browser" "${S}/usr/bin/atlantic-browser.bin"

# libsailfishbrowser (versioned + symlinks — SONAME is libsailfishbrowser.so.1)
mkdir -p "${S}/usr/lib64"
cp -a "${BROWSER_SRC}/build_wpe/libsailfishbrowser.so.1.0.0" "${S}/usr/lib64/"
ln -sfn libsailfishbrowser.so.1.0.0 "${S}/usr/lib64/libsailfishbrowser.so.1.0"
ln -sfn libsailfishbrowser.so.1.0.0 "${S}/usr/lib64/libsailfishbrowser.so.1"
ln -sfn libsailfishbrowser.so.1.0.0 "${S}/usr/lib64/libsailfishbrowser.so"

# QML files
mkdir -p "${S}/usr/share/atlantic-browser"
cp -a "${BROWSER_SRC}/apps/browser/qml/browser.qml" "${S}/usr/share/atlantic-browser/"
cp -a "${BROWSER_SRC}/apps/browser/qml/browser-silica-main-smoke.qml" "${S}/usr/share/atlantic-browser/"
cp -a "${BROWSER_SRC}/apps/browser/qml/browser-minimal.qml" "${S}/usr/share/atlantic-browser/"
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
X-MeeGo-Logical-Id=atlantic-browser-ap-name
X-MeeGo-Translation-Catalog=atlantic-browser
Icon=icon-launcher-browser
Exec=/usr/bin/atlantic-browser %U
Comment=Atlantic Browser (WPE WebKit)
MimeType=text/html;application/xhtml+xml;application/xml;text/xml;x-scheme-handler/http;x-scheme-handler/https;
X-Maemo-Service=org.atlantic.browser.ui
X-Maemo-Object-Path=/ui
X-Maemo-Method=org.atlantic.browser.ui.openUrl

[X-Sailjail]
Permissions=Internet;Audio
OrganizationName=org.sailfishos
ApplicationName=browser
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
OrganizationName=org.sailfishos
ApplicationName=browser
EOF

fpm_rpm atlantic-browser "$ATLANTIC_BROWSER_VERSION" "Atlantic Browser (WPE WebKit engine)" "$S" \
    --depends wpewebkit2 \
    --depends wpewebkit2-qt5 \
    --depends wpe-sfos-compat

# ===========================================================================
echo ""
echo "All RPMs built successfully:"
ls -lh "$OUT"/*.rpm
