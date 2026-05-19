#!/bin/bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

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

gem list fpm | grep -q fpm || gem install --no-document fpm
echo "Build tools ready."

echo ""
echo "--- [2] Setting up SFOS ${SFOS_SYSROOT_VERSION} aarch64 sysroot ---"
if [ ! -d "${SYSROOT}/usr/include" ]; then
    mkdir -p "${SYSROOT}"
    sysroot_url="https://releases.sailfishos.org/sdk/targets/Sailfish_OS-${SFOS_SYSROOT_VERSION}-Sailfish_SDK_Target-aarch64.tar.7z"
    sysroot_tar="/tmp/Sailfish_OS-${SFOS_SYSROOT_VERSION}-Sailfish_SDK_Target-aarch64.tar"
    echo "  Downloading sysroot (177 MB)..."
    curl -L --progress-bar "${sysroot_url}" -o /tmp/sfos-sysroot.tar.7z
    echo "  Extracting..."
    cd "${SYSROOT}"
    7z x /tmp/sfos-sysroot.tar.7z -so | tar -x --numeric-owner 2>/dev/null || {
        7z e /tmp/sfos-sysroot.tar.7z -o/tmp -y
        tar -xf "${sysroot_tar}" -C "${SYSROOT}" --numeric-owner
    }
    rm -f /tmp/sfos-sysroot.tar.7z "${sysroot_tar}"
    echo "  Sysroot ready."
else
    echo "  Sysroot already present."
fi

echo ""
echo "--- [3] Cloning repositories ---"
mkdir -p "${WORK}"

if [ ! -d "${BUILD_TOOLS}/.git" ]; then
    git clone https://github.com/SpecSierra/wpe-sfos-build "${BUILD_TOOLS}"
else
    echo "  wpe-sfos-build already cloned"
fi

if [ ! -d "${BROWSER_SRC}/.git" ]; then
    git clone -b next https://github.com/SpecSierra/sailfish-browser "${BROWSER_SRC}"
else
    echo "  sailfish-browser already cloned"
fi

mkdir -p "${WPE_PREFIX}"
