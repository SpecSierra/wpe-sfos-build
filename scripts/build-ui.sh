#!/bin/bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

WPE_SOURCE_DIR="${WPE_SOURCE_DIR:-${LEGACY_WPE_SOURCE_DIR}}"

echo ""
echo "--- [11] Setting up Qt5 symlinks ---"
ln -sfn "${SYSROOT}/usr/share/qt5" /usr/share/qt5 2>/dev/null || true
ln -sfn "${SYSROOT}/usr/lib64/qt5" /usr/lib64/qt5 2>/dev/null || true
ln -sfn "${SYSROOT}/usr/include/qt5" /usr/include/qt5 2>/dev/null || true
for lib in libQt5Core.so.5 libQt5Xml.so.5 libicui18n.so.70 libicuuc.so.70 libicudata.so.70 libpcre16.so.0; do
    [ -f "${SYSROOT}/usr/lib64/${lib}" ] && \
        ln -sfn "${SYSROOT}/usr/lib64/${lib}" "/usr/lib/${lib}" 2>/dev/null || true
done

echo ""
echo "--- [12] Building sailfish-browser (atlantic-browser) ---"
cd "${BROWSER_SRC}"
mkdir -p build_browser build_wpe

export PATH="${SYSROOT}/usr/lib64/qt5/bin:${PATH}"
export PKG_CONFIG_SYSROOT_DIR="${SYSROOT}"
export PKG_CONFIG_PATH="${SYSROOT}/usr/lib64/pkgconfig:${WPE_PREFIX}/lib/pkgconfig"

rm -rf build
mkdir build
cd build
qmake -spec "${SYSROOT}/usr/share/qt5/mkspecs/linux-g++" \
    ../sailfish-browser.pro \
    "CONFIG+=release" \
    "QMAKE_CXX=g++ --sysroot=${SYSROOT}" \
    "QMAKE_CC=gcc --sysroot=${SYSROOT}" \
    "QMAKE_LINK=g++ --sysroot=${SYSROOT}" \
    "WPE_SFOS_PREFIX=${WPE_PREFIX}" \
    "SFOS_SYSROOT=${SYSROOT}" \
    "WPE_SOURCE_DIR=${WPE_SOURCE_DIR}"

make -C apps/lib -j"${NPROC}"
make -C apps/browser -j"${NPROC}"

cd "${BROWSER_SRC}"
find build -name "atlantic-browser" -not -name "*.o" -type f \
    -exec cp {} build_browser/atlantic-browser \; 2>/dev/null || true
find build -name "libatlanticbrowser.so*" -type f \
    -exec cp {} build_wpe/ \; 2>/dev/null || true
find build -name "*.qm" -exec cp {} build_browser/ \; 2>/dev/null || true

echo "  sailfish-browser built."
