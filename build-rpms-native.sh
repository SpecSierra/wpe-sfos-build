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
source "${SCRIPT_DIR}/deploy/runtime-common.sh"

OUT="${OUT:-/tmp/wpe-sfos-rpms}"
STAGING="${STAGING:-/tmp/wpe-sfos-stage}"
PACKAGE_RUNTIME_PREFIX="${PACKAGE_RUNTIME_PREFIX:-/opt/wpe-sfos}"
ATLANTIC_RUNTIME_PREFIX="${PACKAGE_RUNTIME_PREFIX}"
CONTENT_BLOCKER_DATA_DIR="${SCRIPT_DIR}/data/content-blocker"

mkdir -p "$OUT"

maybe_patch_glibc_versions() {
    [ "${PATCH_GLIBC_VERSIONS}" = "1" ] || return 0
        python3 "${SCRIPT_DIR}/patch-glibc-versions.py" "$@"
}

if [ "${USE_COW_STRING_COMPAT:-0}" = "1" ]; then
    echo "ERROR: USE_COW_STRING_COMPAT is no longer supported in the SFOS ${SFOS_SYSROOT_VERSION} default path." >&2
    echo "       The opaque prebuilt libcow_string_compat shim has been removed; keep the flag disabled." >&2
    exit 1
fi

WPE_COMPAT_PRELOAD="$(atlantic_build_ld_preload)"
WPE_COMPAT_LIBRARY_PATH="$(atlantic_default_library_path)"
WPE_HELPER_LIBRARY_PATH="$(atlantic_default_helper_library_path)"

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
        "${PACKAGE_RUNTIME_PREFIX}/libexec/wpe-webkit-2.0"
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
    local iteration="${RPM_ITERATION:-1}"

    # Write ldconfig scripts
    local post="${STAGING}/post-${name}.sh" postun="${STAGING}/postun-${name}.sh"
    printf '#!/bin/sh\n/sbin/ldconfig || :\n' > "$post"
    printf '#!/bin/sh\n/sbin/ldconfig || :\n' > "$postun"

    echo "==> Building RPM: ${name}-${version}-${iteration}"
    fpm -s dir -t rpm \
        -n "$name" \
        -v "$version" \
        --iteration "${iteration}" \
        --architecture aarch64 \
        --rpm-summary "$summary" \
        --after-install "$post" \
        --after-remove "$postun" \
        --force \
        --package "${OUT}/${name}-${version}-${iteration}.aarch64.rpm" \
        "$@" \
        -C "$stage_root" .
    echo "    -> ${OUT}/${name}-${version}-${iteration}.aarch64.rpm"
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

# WOFF2 runtime shared libraries are required when USE_WOFF2=ON.
# Bundle them into /usr/lib64 so Atlantic can start on stock SFOS images.
stage_shared_library_family "/usr/lib/aarch64-linux-gnu/libwoff2common.so" /usr/lib64 "$S"
stage_shared_library_family "/usr/lib/aarch64-linux-gnu/libwoff2dec.so" /usr/lib64 "$S"
patch_staged_library_family "${S}/usr/lib64/libwoff2common.so"
patch_staged_library_family "${S}/usr/lib64/libwoff2dec.so"

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

# Shared runtime environment for generated wrappers.
mkdir -p "${S}${PACKAGE_RUNTIME_PREFIX}/libexec/atlantic"
install -m 755 "${SCRIPT_DIR}/deploy/runtime-common.sh" \
    "${S}${PACKAGE_RUNTIME_PREFIX}/libexec/atlantic/runtime-common.sh"

# Wrapper scripts for helper processes (set runtime env and launch the real helper).
mkdir -p "${S}${PACKAGE_RUNTIME_PREFIX}/libexec/wpe-webkit-2.0"
for helper in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
    cat > "${S}${PACKAGE_RUNTIME_PREFIX}/libexec/wpe-webkit-2.0/${helper}" <<WRAPPER
#!/bin/sh
. "${PACKAGE_RUNTIME_PREFIX}/libexec/atlantic/runtime-common.sh"
ATLANTIC_LD_PRELOAD='${WPE_COMPAT_PRELOAD}'
ATLANTIC_LD_LIBRARY_PATH='${WPE_HELPER_LIBRARY_PATH}'
atlantic_export_helper_env
exec "${ATLANTIC_WPE_HELPER_DIR}/${helper}" "\$@"
WRAPPER
    chmod 755 "${S}${PACKAGE_RUNTIME_PREFIX}/libexec/wpe-webkit-2.0/${helper}"
done

# Inspector resource (not MiniBrowser)
mkdir -p "${S}/usr/share/wpe-webkit-2.0"
cp -a "${WPE_PREFIX}/share/wpe-webkit-2.0/inspector.gresource" \
      "${S}/usr/share/wpe-webkit-2.0/"
if [ -d "${WPE_PREFIX}/share/wpe-webkit-2.0/build-config" ]; then
    stage_cp "${WPE_PREFIX}/share/wpe-webkit-2.0/build-config" /usr/share/wpe-webkit-2.0 "$S"
fi

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
COMPAT_SRC="${SCRIPT_DIR}/shims/compat"
COMPAT_BUILD="${STAGING}/compat-build"
rm -rf "$COMPAT_BUILD"; mkdir -p "$COMPAT_BUILD"

CC=gcc
CFLAGS="-O2 -march=armv8-a -mtune=cortex-a73.cortex-a53 -fPIC -fvisibility=hidden"
SHARED="-shared -Wl,--allow-shlib-undefined"

for lib in \
    "libsigill_skip.so:libsigill_skip.c"
do
    name="${lib%%:*}"; src="${lib##*:}"
    $CC $CFLAGS $SHARED -o "${COMPAT_BUILD}/${name}" "${COMPAT_SRC}/${src}"
done

# libegl-stubs.so: must NOT use -fvisibility=hidden — symbols must be globally
# visible so dlsym(RTLD_DEFAULT, "eglCreateSync") finds them in patched libepoxy
$CC -O2 -march=armv8-a -mtune=cortex-a73.cortex-a53 -fPIC $SHARED \
    -o "${COMPAT_BUILD}/libegl-stubs.so" "${COMPAT_SRC}/libegl-stubs.c"

# libglibc-compat.so: needs version script (GLIBC_2.17 + GLIBC_2.34 sections)
# and must export dlopen/dlsym/dlerror@GLIBC_2.34 for binaries built on glibc 2.34+
if [ "${USE_GLIBC_COMPAT}" = "1" ]; then
    $CC -O2 -march=armv8-a -mtune=cortex-a73.cortex-a53 -fPIC $SHARED \
        -Wl,--version-script="${COMPAT_SRC}/libglibc-compat.map" \
        -o "${COMPAT_BUILD}/libglibc-compat.so" "${COMPAT_SRC}/libglibc-compat.c" \
        -ldl
fi

# GLib compat: provides g_once_init_enter/leave_pointer absent from Jolla's GLib 2.78.4 build
# Must link against SFOS libglib-2.0 so the wrappers call the real SFOS implementation
if [ "${USE_GLIB_COMPAT}" = "1" ]; then
    $CC -O2 -march=armv8-a -mtune=cortex-a73.cortex-a53 -fPIC $SHARED \
        --sysroot="${SFOS_SYSROOT}" \
        -Wl,-soname,libglib-compat.so \
        -o "${COMPAT_BUILD}/libglib-compat.so" "${COMPAT_SRC}/libglib_compat.c" \
        -L"${SFOS_SYSROOT}/usr/lib64" -lglib-2.0
    ln -sfn libglib-compat.so "${COMPAT_BUILD}/libglib-compat-preload.so"
fi

# Stub: libgssapi_krb5.so.2 (GSSAPI for libsoup3 — always returns unavailable on SFOS)
# Note: must NOT use -fvisibility=hidden here — version-script requires GLOBAL symbols
$CC -O2 -march=armv8-a -mtune=cortex-a73.cortex-a53 -fPIC $SHARED \
    -Wl,--version-script="${COMPAT_SRC}/libgssapi_krb5.map" \
    -Wl,-soname,libgssapi_krb5.so.2 \
    -o "${COMPAT_BUILD}/libgssapi_krb5.so.2" "${COMPAT_SRC}/libgssapi_krb5_stub.c"
ln -sfn libgssapi_krb5.so.2 "${COMPAT_BUILD}/libgssapi_krb5.so"

# Stub: libharfbuzz-icu.so.0 (avoids pulling in libicuuc.so.74 which SFOS doesn't have)
# Note: must NOT use -fvisibility=hidden here — symbols must be globally visible
$CC -O2 -march=armv8-a -mtune=cortex-a73.cortex-a53 -fPIC $SHARED \
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

# Keep shim preload/library-path scoped to Atlantic launcher/helper wrappers only.
# Global nemo session injection breaks unrelated services (e.g. PulseAudio).

fpm_rpm wpe-sfos-compat "$WPE_SFOS_COMPAT_VERSION" "SFOS compatibility shims for WPE WebKit" "$S"

# ===========================================================================
# 7. atlantic-browser
# ===========================================================================
echo "--- Staging atlantic-browser ---"
S="${STAGING}/atlantic-browser"; rm -rf "$S"; mkdir -p "$S"

CONTENT_BLOCKER_BUILD_DIR="${STAGING}/content-blocker-build"
CONTENT_BLOCKER_JSON="${CONTENT_BLOCKER_BUILD_DIR}/content-blocker.json"
rm -rf "${CONTENT_BLOCKER_BUILD_DIR}"
mkdir -p "${CONTENT_BLOCKER_BUILD_DIR}"
python3 "${SCRIPT_DIR}/easylist-to-webkit.py" \
    "${CONTENT_BLOCKER_DATA_DIR}/easylist.txt" \
    --max-rules 10000 \
    -o "${CONTENT_BLOCKER_BUILD_DIR}/easylist.json"
python3 "${SCRIPT_DIR}/easylist-to-webkit.py" \
    "${CONTENT_BLOCKER_DATA_DIR}/easyprivacy.txt" \
    --max-rules 5000 \
    -o "${CONTENT_BLOCKER_BUILD_DIR}/easyprivacy.json"
python3 - "${CONTENT_BLOCKER_BUILD_DIR}/easylist.json" \
    "${CONTENT_BLOCKER_BUILD_DIR}/easyprivacy.json" \
    "${CONTENT_BLOCKER_JSON}" <<'PY'
import json
import sys
from pathlib import Path

easylist_path = Path(sys.argv[1])
easyprivacy_path = Path(sys.argv[2])
output_path = Path(sys.argv[3])

rules = json.loads(easylist_path.read_text()) + json.loads(easyprivacy_path.read_text())
output_path.write_text(json.dumps(rules, indent=2))
print(f"Wrote {len(rules)} content blocker rules to {output_path}")
PY

# Binary
mkdir -p "${S}/usr/bin"
cp -a "${BROWSER_SRC}/build_browser/atlantic-browser" "${S}/usr/bin/"

# WPE launcher environment wrapper
cat > "${S}/usr/bin/atlantic-browser-env" <<LAUNCHER
#!/bin/sh
. "${PACKAGE_RUNTIME_PREFIX}/libexec/atlantic/runtime-common.sh"
ATLANTIC_LD_PRELOAD='${WPE_COMPAT_PRELOAD}'
ATLANTIC_LD_LIBRARY_PATH='${WPE_HELPER_LIBRARY_PATH}'
atlantic_export_browser_env
# Pin to big cores (Kryo 260 Gold / A73 @ 2.0 GHz) on Snapdragon 665.
if command -v taskset >/dev/null 2>&1; then
    exec taskset -c 4-7 /usr/bin/atlantic-browser.bin "\$@"
else
    exec /usr/bin/atlantic-browser.bin "\$@"
fi
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
cp -a "${BROWSER_SRC}/data/icon-launcher-browser.png" "${S}/usr/share/atlantic-browser/data/"
cp -a "${CONTENT_BLOCKER_JSON}"                      "${S}/usr/share/atlantic-browser/content-blocker.json"

# Launcher icon
mkdir -p "${S}/usr/share/icons/hicolor/86x86/apps"
cp -a "${BROWSER_SRC}/data/icon-launcher-browser.png" \
    "${S}/usr/share/icons/hicolor/86x86/apps/icon-launcher-atlantic.png"

# Desktop file
mkdir -p "${S}/usr/share/applications"
cat > "${S}/usr/share/applications/atlantic-browser.desktop" << 'DESKTOP'
[Desktop Entry]
Type=Application
Name=Atlantic
X-MeeGo-Logical-Id=atlantic-browser-ap-name
X-MeeGo-Translation-Catalog=atlantic-browser
Icon=icon-launcher-atlantic
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
