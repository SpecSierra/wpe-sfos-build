#!/usr/bin/env bash
# setup-rpmbuild.sh — Stage all source tarballs for the WPE SFOS RPM build.
#
# Run this once before using `sfdk build` or `rpmbuild`.
# All tarballs land in ~/rpmbuild/SOURCES/ as expected by the spec files.
#
# Prerequisites:
#   git, meson (for version queries), curl/wget, bzip2, xz
#
# Usage:
#   bash setup-rpmbuild.sh [--sources-dir /path/to/rpmbuild/SOURCES]
#
set -euo pipefail

SOURCES_DIR="${1:-$HOME/rpmbuild/SOURCES}"
mkdir -p "$SOURCES_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Staging RPM sources to: $SOURCES_DIR"

# ---------------------------------------------------------------------------
# 1. wpe-sfos-compat — create tarball from this git repo
# ---------------------------------------------------------------------------
echo ""
echo "--- wpe-sfos-compat 1.0.0 ---"
(
  cd "$SCRIPT_DIR"
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "ERROR: $SCRIPT_DIR is not a git repo" >&2
    exit 1
  fi
  git archive --prefix=wpe-sfos-compat-1.0.0/ HEAD \
    | bzip2 > "$SOURCES_DIR/wpe-sfos-compat-1.0.0.tar.bz2"
  echo "  Created wpe-sfos-compat-1.0.0.tar.bz2"
)

# ---------------------------------------------------------------------------
# 2. libwpe 1.17.0
# ---------------------------------------------------------------------------
echo ""
echo "--- libwpe 1.17.0 ---"
if [ ! -f "$SOURCES_DIR/libwpe-1.17.0.tar.xz" ]; then
  TMP=$(mktemp -d)
  git clone --depth=1 --branch 1.17.0 \
    https://github.com/WebPlatformForEmbedded/libwpe "$TMP/libwpe" \
    2>/dev/null || {
      echo "  Tag 1.17.0 not found, cloning HEAD..."
      git clone --depth=1 https://github.com/WebPlatformForEmbedded/libwpe "$TMP/libwpe"
    }
  git -C "$TMP/libwpe" archive --prefix=libwpe-1.17.0/ HEAD \
    | xz > "$SOURCES_DIR/libwpe-1.17.0.tar.xz"
  rm -rf "$TMP"
  echo "  Created libwpe-1.17.0.tar.xz"
else
  echo "  Already present: libwpe-1.17.0.tar.xz"
fi

# ---------------------------------------------------------------------------
# 3. libepoxy 1.5.11
# ---------------------------------------------------------------------------
echo ""
echo "--- libepoxy 1.5.11 ---"
if [ ! -f "$SOURCES_DIR/libepoxy-1.5.11.tar.xz" ]; then
  TMP=$(mktemp -d)
  git clone --depth=1 --branch 1.5.11 \
    https://github.com/anholt/libepoxy "$TMP/libepoxy" \
    2>/dev/null || {
      echo "  Tag 1.5.11 not found, cloning HEAD..."
      git clone --depth=1 https://github.com/anholt/libepoxy "$TMP/libepoxy"
    }
  git -C "$TMP/libepoxy" archive --prefix=libepoxy-1.5.11/ HEAD \
    | xz > "$SOURCES_DIR/libepoxy-1.5.11.tar.xz"
  rm -rf "$TMP"
  echo "  Created libepoxy-1.5.11.tar.xz"
else
  echo "  Already present: libepoxy-1.5.11.tar.xz"
fi

# ---------------------------------------------------------------------------
# 4. WPEBackend-fdo 1.17.0
# ---------------------------------------------------------------------------
echo ""
echo "--- wpebackend-fdo 1.17.0 ---"
if [ ! -f "$SOURCES_DIR/wpebackend-fdo-1.17.0.tar.xz" ]; then
  TMP=$(mktemp -d)
  git clone --depth=1 --branch 1.17.0 \
    https://github.com/igalia/WPEBackend-fdo "$TMP/wpebackend-fdo" \
    2>/dev/null || {
      echo "  Tag 1.17.0 not found, cloning HEAD..."
      git clone --depth=1 https://github.com/igalia/WPEBackend-fdo "$TMP/wpebackend-fdo"
    }
  git -C "$TMP/wpebackend-fdo" archive --prefix=wpebackend-fdo-1.17.0/ HEAD \
    | xz > "$SOURCES_DIR/wpebackend-fdo-1.17.0.tar.xz"
  rm -rf "$TMP"
  echo "  Created wpebackend-fdo-1.17.0.tar.xz"
else
  echo "  Already present: wpebackend-fdo-1.17.0.tar.xz"
fi

# ---------------------------------------------------------------------------
# 5. WPEWebKit 2.50.5
# ---------------------------------------------------------------------------
echo ""
echo "--- wpewebkit 2.50.5 ---"
if [ ! -f "$SOURCES_DIR/wpewebkit-2.50.5.tar.xz" ]; then
  echo "  Downloading from wpewebkit.org..."
  curl -L --progress-bar \
    "https://wpewebkit.org/release/wpewebkit-2.50.5.tar.xz" \
    -o "$SOURCES_DIR/wpewebkit-2.50.5.tar.xz"
  echo "  Downloaded wpewebkit-2.50.5.tar.xz"
else
  echo "  Already present: wpewebkit-2.50.5.tar.xz"
fi

# ---------------------------------------------------------------------------
# Copy spec helper files (toolchain, patches, scripts)
# ---------------------------------------------------------------------------
echo ""
echo "--- Copying spec helper files ---"
for f in \
    sfos-toolchain.cmake \
    sfos-meson-cross.ini \
    webkit-quirks-no-video.patch \
    qt5-plugin-gnuinstalldirs.patch \
    patch-glibc-versions.py; do
  cp -v "$SCRIPT_DIR/$f" "$SOURCES_DIR/$f"
done

echo ""
echo "==> Done. All sources staged in: $SOURCES_DIR"
echo ""
echo "Build order:"
echo "  sfdk build rpm/libwpe.spec"
echo "  sfdk build rpm/libepoxy.spec"
echo "  sfdk build rpm/wpebackend-fdo.spec"
echo "  sfdk build rpm/wpe-sfos-compat.spec"
echo "  sfdk build rpm/wpewebkit2.spec"
echo "  sfdk build rpm/wpewebkit2-qt5.spec"
echo "  sfdk build sailfish-browser/rpm/sailfish-browser.spec"
