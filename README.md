# wpe-sfos-build

Compatibility shims, cross-compilation toolchain, and build tooling for running
**WPE WebKit 2.50.5** on **Sailfish OS 5.0 (aarch64)**.

This repo is the glue layer between stock WPE WebKit and the constraints of SFOS:
older glibc (2.30), limited CPU instruction set (ARMv8.0-A), and the sailjail
sandbox. It accompanies the browser source at
[SpecSierra/sailfish-browser](https://github.com/SpecSierra/sailfish-browser).

> **Quickstart:** On a native aarch64 Ubuntu 24.04 machine, run `bash build-all.sh`
> to build the entire stack and generate installable RPMs in `/tmp/wpe-sfos-rpms/`.

---

## Target Device

| | |
|---|---|
| Device | Sony Xperia 10 II |
| SoC | Snapdragon 665 (Cortex-A53/A55, ARMv8.0-A) |
| OS | Sailfish OS 5.0.0.72 |
| Arch | aarch64 |
| glibc | 2.30 |
| Qt | 5.6.3 (system) |

---

## Repository Contents

| File | Purpose |
|---|---|
| `build-all.sh` | **Master build script** — builds full WPE stack natively on aarch64 Ubuntu 24.04 |
| `build-rpms-native.sh` | Stages built artifacts and packages them as RPMs |
| `native-meson.ini` | Meson native-file for libwpe/libepoxy/WPEBackend-fdo (no cross/sysroot) |
| `sfos-toolchain.cmake` | CMake toolchain for Qt5 plugin + browser (targets SFOS sysroot) |
| `sfos-meson-cross.ini` | Meson cross-file (alternative, requires Wayland headers in sysroot) |
| `libglibc-compat.c` | Shim: glibc 2.31–2.38 symbols missing from SFOS glibc 2.30; also exports `dlopen/dlsym/dlerror@GLIBC_2.34` |
| `libglibc-compat.map` | GNU version script for `libglibc-compat.so` (GLIBC_2.17 + GLIBC_2.34 sections) |
| `libglib_compat.c` | Shim: `g_once_init_enter/leave_pointer` missing from Jolla's GLib 2.78.4 build |
| `libgetauxval_fix.c` | Shim: fix `getauxval(AT_HWCAP2/AT_MINSIGSTKSZ)` on SFOS aarch64 |
| `libgetauxval_fix2.c` | Variant of the above for WebProcess/NetworkProcess helpers |
| `libsigill_skip.c` | Shim: skip SIGILL-triggering CPU feature probes (ARMv8.1+ instructions) |
| `libsigill_skip2.c` | Variant for libWPEBackend-fdo feature probes |
| `libsigill_skip3.c` | Variant for libwpe feature probes |
| `libexecve_wrap.c` | Shim: rewrite `execve()` paths for WebProcess under sailjail |
| `libexecve_wrap2.c` | Variant for NetworkProcess |
| `libegl-stubs.c` | Stub EGL 1.5 symbols missing from SFOS Adreno EGL 1.4 (built **without** `-fvisibility=hidden`) |
| `patch-glibc-versions.py` | Post-link: rewrite `GLIBC_2.3x` ELF VERNEED entries → `GLIBC_2.17` |
| `libepoxy-rtld-default-fallback.patch` | libepoxy patch: fall back to `dlsym(RTLD_DEFAULT)` so `libegl-stubs.so` can satisfy missing EGL symbols |
| `BubblewrapLauncher-sfos-sandbox.patch` | WPEWebKit patch: use `--dev-bind / /` in bubblewrap so shell wrapper scripts work inside the sandbox |
| `qt5-plugin-gnuinstalldirs.patch` | Fixes libqtwpe.so install path on Ubuntu (multiarch) |
| `webkit-quirks-no-video.patch` | WebKit `Quirks.cpp`: guard `HTMLVideoElement` refs with `#if ENABLE(VIDEO)` |
| `wpeqtview-sfos-api.patch` | Adds SFOS-specific signals/methods to `WPEQtView` |
| `easylist-to-webkit.py` | Convert EasyList/uBlock filter lists to WebKit content blocker JSON |

---

## Build Environment Setup

### Host Requirements

- **OS:** Ubuntu 22.04 or 24.04, aarch64 native *(or an aarch64 cross-compiler on x86_64)*
- **Compiler:** GCC 13+ with `aarch64-linux-gnu` target
- **Build tools:** `cmake`, `ninja`, `meson`, `pkg-config`, `python3`
- **Qt:** Qt 5.6 development headers (for building `libqtwpe.so`)

### Sailfish OS Sysroot

Extract the SFOS 5.0.0.62 SDK target into `/opt/sfos-sysroot`:

```bash
# Available from https://releases.sailfishos.org/sdk/targets/
sudo mkdir -p /opt/sfos-sysroot
sudo tar -xf Sailfish_OS-5.0.0.62-Sailfish_SDK_Target-aarch64.tar.7z \
     -C /opt/sfos-sysroot
```

### Build Prefix

All WPE libraries are installed into `/opt/wpe-sfos` during the build.
This directory is **not** deployed to the device — it is only used at build time
as a staging area. The final artifacts are copied from here into the deployment
tarball.

```bash
sudo mkdir -p /opt/wpe-sfos
sudo chown $USER /opt/wpe-sfos
```

---

## Build Order

Dependencies must be built in this order:

```
1. libwpe
2. libepoxy
3. WPEBackend-fdo
4. WPEWebKit 2.50.5  (+ Qt5 plugin)
5. compat shims      (this repo)
6. sailfish-browser
```

---

### 1. libwpe

```bash
git clone https://github.com/WebPlatformForEmbedded/libwpe
cd libwpe
meson setup build \
    --cross-file /path/to/wpe-sfos-build/sfos-meson-cross.ini \
    --prefix /opt/wpe-sfos \
    --buildtype release
ninja -C build install
```

### 2. libepoxy

```bash
git clone https://github.com/anholt/libepoxy
cd libepoxy
meson setup build \
    --cross-file /path/to/wpe-sfos-build/sfos-meson-cross.ini \
    --prefix /opt/wpe-sfos \
    --buildtype release \
    -Dx11=false -Dglx=no -Degl=yes
ninja -C build install
```

### 3. WPEBackend-fdo

```bash
git clone https://github.com/igalia/WPEBackend-fdo
cd WPEBackend-fdo
meson setup build \
    --cross-file /path/to/wpe-sfos-build/sfos-meson-cross.ini \
    --prefix /opt/wpe-sfos \
    --buildtype release
ninja -C build install
```

### 4. WPE WebKit 2.50.5

Download the release tarball (not the full WebKit git tree — it is 10+ GB):

```bash
wget https://wpewebkit.org/releases/wpewebkit-2.50.5.tar.xz
tar -xf wpewebkit-2.50.5.tar.xz
cd wpewebkit-2.50.5
```

Apply the Quirks.cpp patch (required when `ENABLE_VIDEO=OFF`):

```bash
patch -p1 < /path/to/wpe-sfos-build/webkit-quirks-no-video.patch
```

Configure and build:

```bash
PKG_CONFIG_PATH=/opt/wpe-sfos/lib/pkgconfig \
cmake -B WebKitBuild/Release -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE=/path/to/wpe-sfos-build/sfos-toolchain.cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/opt/wpe-sfos \
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

ninja -C WebKitBuild/Release
ninja -C WebKitBuild/Release install

# libWPEInjectedBundle.so is not installed by ninja install — copy manually
cp WebKitBuild/Release/lib/libWPEInjectedBundle.so /opt/wpe-sfos/lib/
```

After installing, patch all binaries to downgrade GLIBC version requirements:

```bash
python3 /path/to/wpe-sfos-build/patch-glibc-versions.py \
    /opt/wpe-sfos/lib/libWPEWebKit-2.0.so.1.*.* \
    /opt/wpe-sfos/lib/libWPEInjectedBundle.so \
    /opt/wpe-sfos/libexec/wpe-webkit-2.0/WPEWebProcess \
    /opt/wpe-sfos/libexec/wpe-webkit-2.0/WPENetworkProcess \
    /opt/wpe-sfos/libexec/wpe-webkit-2.0/WPEGPUProcess
```

> ⚠️ WPE WebKit is a large build. Expect 60–90 minutes on an 8-core machine.

#### Qt5 WPE Plugin (libqtwpe.so)

The Qt5 WPE plugin source lives inside the WPE WebKit tarball at
`Source/WebKit/UIProcess/API/wpe/qt5/`. Build it separately with Qt 5.6:

```bash
# qmake is inside the SFOS sysroot — add it to PATH first
export PATH="/opt/sfos-sysroot/usr/lib64/qt5/bin:$PATH"

cd wpewebkit-2.50.5/Source/WebKit/UIProcess/API/wpe/qt5

# Apply GNUInstallDirs patch (fixes libqtwpe.so install path)
patch -p4 < /path/to/wpe-sfos-build/qt5-plugin-gnuinstalldirs.patch

PKG_CONFIG_PATH=/opt/wpe-sfos/lib/pkgconfig \
cmake -B build -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE=/path/to/wpe-sfos-build/sfos-toolchain.cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/opt/wpe-sfos \
    -DCMAKE_INSTALL_LIBDIR=lib
ninja -C build install
```

This produces `libqtwpe.so` and `qmldir` under
`/opt/wpe-sfos/lib/qt5/qml/org/wpewebkit/qtwpe/`.

### 5. Compat Shims

Build all shims with the aarch64 cross-compiler targeting the SFOS sysroot:

```bash
SYSROOT=/opt/sfos-sysroot
CC="gcc --sysroot=$SYSROOT"
CFLAGS="-O2 -march=armv8-a -fPIC -shared"
LDFLAGS="-Wl,--allow-shlib-undefined --sysroot=$SYSROOT"

$CC $CFLAGS $LDFLAGS -o libglibc-compat.so       libglibc-compat.c
$CC $CFLAGS $LDFLAGS -o libgetauxval_fix.so       libgetauxval_fix.c
$CC $CFLAGS $LDFLAGS -o libgetauxval_fix2.so      libgetauxval_fix2.c
$CC $CFLAGS $LDFLAGS -o libsigill_skip.so         libsigill_skip.c
$CC $CFLAGS $LDFLAGS -o libsigill_skip2.so        libsigill_skip2.c
$CC $CFLAGS $LDFLAGS -o libsigill_skip3.so        libsigill_skip3.c
$CC $CFLAGS $LDFLAGS -o libexecve_wrap.so         libexecve_wrap.c  -ldl
$CC $CFLAGS $LDFLAGS -o libexecve_wrap2.so        libexecve_wrap2.c -ldl
$CC $CFLAGS $LDFLAGS -o libegl-stubs.so           libegl-stubs.c
```

#### Patch GLIBC version tags

After building all WPE `.so` files, strip references to newer glibc symbols.
Pass each file explicitly:

```bash
python3 patch-glibc-versions.py \
    /opt/wpe-sfos/lib/libWPEWebKit-2.0.so.*.* \
    /opt/wpe-sfos/lib/libWPEBackend-fdo-1.0.so.*.* \
    /opt/wpe-sfos/lib/libwpe-1.0.so.*.* \
    /opt/wpe-sfos/libexec/wpewebkit/WPEWebProcess \
    /opt/wpe-sfos/libexec/wpewebkit/WPENetworkProcess \
    /opt/wpe-sfos/libexec/wpewebkit/WPEGPUProcess
```

> ℹ️ The script can also be run with no arguments to patch the original
> workspace build tree at `BUILD_ROOT` / `ARTIFACTS_ROOT` defined at the
> top of `patch-glibc-versions.py` — edit those variables if your paths differ.

### 6. sailfish-browser

Clone the browser source (branch `next`):

```bash
git clone -b next https://github.com/SpecSierra/sailfish-browser
cd sailfish-browser
```

qmake from the SFOS sysroot expects to find Qt5 module definitions at `/usr/share/qt5`
and `/usr/lib64/qt5`. Symlink the sysroot paths once:

```bash
sudo ln -sfn /opt/sfos-sysroot/usr/share/qt5 /usr/share/qt5
sudo ln -sfn /opt/sfos-sysroot/usr/lib64/qt5 /usr/lib64/qt5
sudo ln -sfn /opt/sfos-sysroot/usr/include/qt5 /usr/include/qt5
```

The sysroot Qt5 tools (e.g. `lupdate`) are aarch64 binaries and run natively on the
build host, but need sysroot libraries on the host's library path. Create these
symlinks once:

```bash
for lib in libQt5Core.so.5 libQt5Xml.so.5 libicui18n.so.70 libicuuc.so.70 libicudata.so.70 libpcre16.so.0; do
    sudo ln -sfn /opt/sfos-sysroot/usr/lib64/$lib /usr/lib/$lib
done
```

Configure and build:

```bash
export PATH="/opt/sfos-sysroot/usr/lib64/qt5/bin:$PATH"
export PKG_CONFIG_SYSROOT_DIR=/opt/sfos-sysroot
export PKG_CONFIG_PATH=/opt/sfos-sysroot/usr/lib64/pkgconfig:/opt/wpe-sfos/lib/pkgconfig

mkdir build && cd build
qmake -spec /opt/sfos-sysroot/usr/share/qt5/mkspecs/linux-g++ \
    ../sailfish-browser.pro \
    "CONFIG+=release" \
    "QMAKE_CXX=g++ --sysroot=/opt/sfos-sysroot" \
    "QMAKE_CC=gcc --sysroot=/opt/sfos-sysroot" \
    "QMAKE_LINK=g++ --sysroot=/opt/sfos-sysroot" \
    "WPE_SFOS_PREFIX=/opt/wpe-sfos" \
    "SFOS_SYSROOT=/opt/sfos-sysroot" \
    "WPE_SOURCE_DIR=/path/to/wpewebkit-2.50.5"
make -j$(nproc)
```

> **Note:** The `captiveportal` sub-project has not been ported to WPE and will
> fail to build. Build only the core library and binary instead of the full tree:
> ```bash
> make -C apps/lib && make -C apps/browser
> ```

---

## Deployment

Copy the artifacts to the device over SSH. The browser expects all WPE libraries
under `~/wpe-sfos-artifacts/` on the device:

```
~/wpe-sfos-artifacts/
  lib/
    libWPEWebKit-2.0.so*
    libWPEBackend-fdo-1.0.so*
    libwpe-1.0.so*
    libepoxy.so*
    libsoup-3.0.so*
    libglibc-compat.so
    libgetauxval_fix.so
    libsigill_skip.so
    libexecve_wrap.so
    libegl-stubs.so
    qt5/qml/org/wpewebkit/qtwpe/
      libqtwpe.so
      qmldir
```

Launch the browser manually (sailjail disabled — see Known Issues):

```bash
XDG_RUNTIME_DIR=/run/user/100000 \
WAYLAND_DISPLAY=../../display/wayland-0 \
QT_QPA_PLATFORM=wayland \
QT_IM_MODULE=Maliit \
LD_LIBRARY_PATH=/home/defaultuser/wpe-sfos-artifacts/lib \
LD_PRELOAD="libglibc-compat.so libgetauxval_fix.so libsigill_skip.so libegl-stubs.so" \
/usr/bin/sailfish-browser
```

---

## Content Blocker

Convert an EasyList-format filter list to WebKit JSON:

```bash
python3 easylist-to-webkit.py easylist.txt > content-blocker.json
```

Deploy `content-blocker.json` to the device and load it in WPEWebPage via
`WKContentRuleListStore`.

---

## Known Issues & Limitations

| Issue | Status | Notes |
|---|---|---|
| sailjail / invoker | ⚠️ Partial | Bubblewrap sandbox works with `BubblewrapLauncher-sfos-sandbox.patch`; full sailjail profile not yet done |
| GStreamer / video playback | 🔴 Not implemented | WPE built with `ENABLE_VIDEO=OFF` |
| File downloads | 🔴 Not implemented | `webkit_download_*` API hookup planned |
| ARMv8.1+ instruction probes | ✅ Mitigated | `libsigill_skip*.so` shims handle `SIGILL` from CPU feature detection |
| glibc 2.31–2.38 symbols | ✅ Mitigated | `libglibc-compat.so` + `patch-glibc-versions.py` |
| EGL 1.5 symbols on Adreno EGL 1.4 | ✅ Fixed | `libegl-stubs.so` + libepoxy RTLD_DEFAULT patch |
| `virtualKeyboardHeight` QML property | ⚠️ Missing | `WPEQtView` does not yet expose virtual keyboard height to QML |
| `_mainWindow: webView` QML assignment | ⚠️ Harmless warning | `WebView` QML type cannot be assigned to `QWindow`; cosmetic only |

---

## Build Notes & Troubleshooting

Issues discovered during development on a native aarch64 Ubuntu 24.04 host
targeting SFOS 5.0.0.72. Documented here so others don't hit the same walls.

---

### Issue 1 — `libgio-cil-dev` does not exist

**Where:** README host dependency list  
**Problem:** `libgio-cil-dev` does not exist on Ubuntu 22.04 or 24.04. GIO/GObject
headers are included in `libglib2.0-dev`.  
**Fix:** Remove `libgio-cil-dev`; `libglib2.0-dev` is sufficient.

---

### Issue 2 — libwpe meson subproject: xcb-xkb missing on headless host

**Where:** `meson setup` for libwpe  
**Problem:** libwpe bundles libxkbcommon as a subproject. It defaults to building
with X11 support. On a headless Ubuntu build host `xcb-xkb` is absent and meson
aborts.  
**Fix:** Add subproject flags (note the `subprojectname:` prefix):
```
-Dlibxkbcommon:enable-x11=false
-Dlibxkbcommon:enable-wayland=false
-Dlibxkbcommon:enable-tools=false
-Dlibxkbcommon:enable-docs=false
-Dlibxkbcommon:enable-xkbregistry=false
```

---

### Issue 3 — SFOS SDK sysroot lacks Wayland/WPE build deps

**Where:** `sfos-meson-cross.ini` cross-file usage for libwpe/libepoxy/WPEBackend-fdo  
**Problem:** The public SFOS 5.0 SDK Target sysroot is a Qt/Silica app-development
sysroot only. It does **not** include `wayland-client.pc`, `egl.pc`, or other
low-level Wayland/WPE headers. Using the cross-file for base libraries fails:
```
Run-time dependency wayland-client found: NO
ERROR: Dependency "wayland-client" not found
```
**Fix:** Build libwpe, libepoxy, WPEBackend-fdo, and WPEWebKit **natively** against
the Ubuntu 24.04 host system using `native-meson.ini` (no sysroot). Use the SFOS
sysroot **only** for the Qt5 plugin and the sailfish-browser build (which need Qt
5.6.3 + Silica). `build-all.sh` implements this correctly.

---

### Issue 4 — pkg-config multiarch path on Ubuntu 24.04 aarch64

**Where:** `PKG_CONFIG_PATH` in cmake/meson invocations  
**Problem:** On Ubuntu 24.04 aarch64, meson installs `.pc` files under
`$prefix/lib/aarch64-linux-gnu/pkgconfig` (multiarch), not `$prefix/lib/pkgconfig`.
Using only the non-multiarch path misses `wpebackend-fdo-1.0.pc`.  
**Fix:** Set both paths:
```
PKG_CONFIG_PATH=/opt/wpe-sfos/lib/pkgconfig:/opt/wpe-sfos/lib/aarch64-linux-gnu/pkgconfig
```

---

### Issue 5 — WPEWebKit tarball URL returns HTTP 404

**Where:** README download command  
**Problem:** The URL used `release` (singular) which does not exist.  
**Fix:** Correct URL uses `releases` (plural):
```bash
wget https://wpewebkit.org/releases/wpewebkit-2.50.5.tar.xz
```

---

### Issue 6 — WPEWebKit cmake: missing host packages

**Where:** README host requirements  
**Problem:** The following packages are required but were not listed:
`libgcrypt20-dev`, `libgpg-error-dev`, `libwoff-dev`, `libopenjp2-7-dev`,
`liblcms2-dev`, `libhyphen-dev`.  
**Fix:** Add to apt install list before configuring WPEWebKit.

---

### Issue 7 — ICU symbol renaming: Ubuntu 24.04 ICU 74 vs SFOS ICU 70

**Where:** WPEWebKit cmake configuration  
**Problem:** The toolchain sets `U_DISABLE_RENAMING=1`, expecting ICU to export
unversioned symbols (`u_tolower`, `u_charType`, …). Ubuntu 24.04 ships ICU 74
which exports **only** versioned names (`u_tolower_74`, …). This causes ~100+
linker errors.  
**Fix:** Symlink the SFOS sysroot ICU 70 libraries (which export unversioned
symbols) and point cmake at them:
```bash
cd /opt/sfos-sysroot/usr/lib64
ln -sf libicuuc.so.70   libicuuc.so
ln -sf libicui18n.so.70 libicui18n.so
ln -sf libicudata.so.70 libicudata.so
```
Then pass to cmake:
```
-DICU_UC_LIBRARY_RELEASE=/opt/sfos-sysroot/usr/lib64/libicuuc.so
-DICU_I18N_LIBRARY_RELEASE=/opt/sfos-sysroot/usr/lib64/libicui18n.so
-DICU_DATA_LIBRARY_RELEASE=/opt/sfos-sysroot/usr/lib64/libicudata.so
```

---

### Issue 8 — SFOS sysroot missing nemotransferengine-qt5 headers and pkgconfig

**Where:** sailfish-browser-wpe build  
**Problem:** `nemotransferengine-qt5` has no `.pc` file and no public headers in
the sysroot. `qdbusxml2cpp` must generate `transferengineinterface.h` from the
D-Bus XML, and stub headers must be downloaded from
https://github.com/sailfishos/transfer-engine/tree/master/lib.  
**Fix:** Generate headers and create a stub `.pc` file at
`$SFOS_SYSROOT/usr/lib64/pkgconfig/nemotransferengine-qt5.pc`.

---

### Issue 9 — `WPE_SOURCE_DIR` default path incorrect

**Where:** Browser qmake invocation  
**Problem:** `WPE_SOURCE_DIR` defaults to `/workspace/wpewebkit-2.50.5`; actual
checkout is at `/release/workspace/wpewebkit-2.50.5`. Without the correct path
qmake cannot find `WPEQtView.h`.  
**Fix:** Always pass `WPE_SOURCE_DIR=/release/workspace/wpewebkit-2.50.5`
explicitly on the qmake command line.

---

### Issue 10 — Qt `signals` macro conflicts with GLib gdbusintrospection.h

**Where:** sailfish-browser-wpe compilation  
**Problem:** Qt 5.6.3 defines `#define signals public`. GLib's
`<gio/gdbusintrospection.h>` has a field `GDBusSignalInfo **signals`, which
after macro expansion becomes `GDBusSignalInfo **public` — a C++ syntax error.  
**Fix:** Create a shim header placed first in `-I` that uses
`#pragma push_macro("signals") / #undef signals / #include_next / #pragma pop_macro`.

---

### Issue 11 — WPEQtView missing signals and methods

**Where:** sailfish-browser-wpe compilation against WPEWebKit 2.50.5  
**Problem:** The upstream `WPEQtView` API lacks signals and methods expected by
the browser: `setUserAgent`, `setDeviceScaleFactor`, `scrollPositionChanged`,
`faviconUrlChanged`, `selectedTextChanged`, `enterFullscreenRequested`, etc.  
**Fix:** `wpeqtview-sfos-api.patch` adds declarations to `WPEQtView.h` and stub
implementations to `WPEQtView.cpp`.

---

### Issue 12 — SFOS moc binary path differs from Ubuntu path

**Where:** Makefile generated by sailfish-browser qmake  
**Problem:** Generated Makefiles reference moc at `/usr/lib64/qt5/bin/moc`
(SFOS sysroot path). Ubuntu 24.04 places it at `/usr/lib/qt5/bin/moc`.  
**Fix:**
```bash
sudo ln -sfn /opt/sfos-sysroot/usr/lib64/qt5/bin/moc /usr/lib64/qt5/bin/moc
```

---

### Issue 13 — build-rpms-native.sh looks for `libatlanticbrowser.so` but browser builds `libsailfishbrowser.so`

**Where:** `build-rpms-native.sh`, atlantic-browser staging  
**Problem:** The RPM script expects `libatlanticbrowser.so.1.0.0` but `lib.pro`
sets `TARGET = sailfishbrowser`, producing `libsailfishbrowser.so.1.0.0`.  
**Fix:** Set `TARGET = atlanticbrowser` in `lib.pro`.

---

### Issue 14 — wpebackend-fdo pkgconfig: relative symlink breaks staging

**Where:** `build-rpms-native.sh`, wpebackend-fdo staging  
**Problem:** The `.pc` file is in the multiarch path; a relative symlink in
`lib/pkgconfig/` becomes dangling when copied into the staging tree.  
**Fix:** Copy the actual file content:
```bash
cp /opt/wpe-sfos/lib/aarch64-linux-gnu/pkgconfig/wpebackend-fdo-1.0.pc \
   /opt/wpe-sfos/lib/pkgconfig/wpebackend-fdo-1.0.pc
```

---

### Issue 15 — Captiveportal uses old Gecko `DeclarativeWebPage` API

**Where:** `sailfish-browser-wpe/apps/captiveportal/`  
**Problem:** Captiveportal includes `<DeclarativeWebPage>` from qtmozembed — a
Gecko-only API that does not exist in WPE.  
**Fix:** Create compat stub headers:
```cpp
// declarativewebpage.h
typedef WPEWebPage DeclarativeWebPage;
```

---

### Issue 16 — `MDConfItem` not available as Qt-style angle-bracket include

**Where:** sailfish-browser-wpe browser compilation  
**Problem:** Code uses `#include <MDConfItem>` but the sysroot only provides
`mdconfitem.h` (with extension, lowercase).  
**Fix:** Create `apps/core/MDConfItem` (extension-less) containing
`#include "mdconfitem.h"` and ensure `apps/core/` is in the include path.

---

### Issue 17 — build-rpms-native.sh wpebackend-fdo: `cp` with 3 args stages entire host `/usr/lib64`

**Where:** `build-rpms-native.sh`, wpebackend-fdo section  
**Problem:** `cp -a "${WPE_PREFIX}/lib/libWPEBackend-fdo..." /usr/lib64 "$S"` with
two sources copies the library **and** the entire host `/usr/lib64` into the
staging root, inflating the RPM from ~170 KB to 9.5 MB with Ubuntu-native
libraries that cannot run on SFOS.  
**Fix:** Copy only from the multiarch path:
```bash
cp "${WPE_PREFIX}/lib/aarch64-linux-gnu/libWPEBackend-fdo-1.0.so.1.11.0" \
   "${S}/usr/lib64/"
```

---

### Issue 18 — wpebackend-fdo and libsoup-3.0 require GLIBC > 2.30

**Where:** `build-rpms-native.sh` — packaging of wpebackend-fdo and missing deps  
**Problem:** Libraries built on Ubuntu 24.04 require GLIBC 2.38; SFOS has 2.30.
`patch-glibc-versions.py` was called on `libWPEWebKit` but **not** on
`libWPEBackend-fdo`. Several runtime libraries absent from SFOS must be bundled
in `/usr/lib64/wpe-compat/`:
`libsoup-3.0`, `libatomic`, `libjpeg.so.8`, `libharfbuzz-icu`, `libbrotli*`.  
**Fix:** Apply `patch-glibc-versions.py` to all bundled `.so` files. Bundle missing
libs from Ubuntu 24.04 aarch64 into the `wpe-sfos-compat` RPM. Set
`LD_LIBRARY_PATH=/usr/lib64/wpe-compat:/usr/lib64` in the nemo environment conf.

---

### Issue 19 — libepoxy aborts WPEWebProcess: EGL 1.5 symbols missing on Adreno EGL 1.4

**Where:** `libepoxy/src/dispatch_common.c`, `do_dlsym()`  
**Problem:** SFOS Adreno `libEGL.so.1` implements EGL 1.4 only — it lacks
`eglCreateSync`, `eglDestroySync`, `eglClientWaitSync`, etc. libepoxy opens
libEGL via `dlopen("libEGL.so.1", RTLD_LOCAL)` then calls `dlsym(handle, name)`.
Because the handle is `RTLD_LOCAL`, LD_PRELOAD shims **cannot** intercept the
lookup. When `eglCreateSync` returns NULL, libepoxy calls `abort()`, crashing
WPEWebProcess immediately.

**Fix (two parts):**
1. **libepoxy patch** (`libepoxy-rtld-default-fallback.patch`): after the
   handle-specific `dlsym` fails, fall back to `dlsym(RTLD_DEFAULT, name)` so
   LD_PRELOAD stubs in the global namespace are found.
2. **`libegl-stubs.so`**: provides `eglCreateSync` (→ `EGL_NO_SYNC`),
   `eglCreateImage` (→ forwards to `eglCreateImageKHR`), etc. Added to
   `LD_PRELOAD` in the WPEWebProcess wrapper script.

> ⚠️ **Critical:** `libegl-stubs.so` must be built **without** `-fvisibility=hidden`.
> With that flag all symbols are hidden from `dlsym(RTLD_DEFAULT)` and the
> fallback silently fails — WPEWebProcess still crashes.

---

### Issue 20 — libepoxy requires `GLIBC_2.34` (dlopen/dlsym/dlerror) but SFOS has GLIBC 2.30

**Where:** `libepoxy.so.0.0.0` VERNEED section; `build-rpms-native.sh` staging  
**Problem:** libepoxy built on Ubuntu 24.04 has `dlopen@GLIBC_2.34`,
`dlsym@GLIBC_2.34`, `dlerror@GLIBC_2.34` as versioned requirements (glibc 2.34
moved these from `libdl.so.2` to `libc.so.6` under a new version tag). SFOS
glibc 2.30 exports them from `libdl.so.2` as `GLIBC_2.17`. The dynamic linker
checks VERNEED entries against the **named** library, so LD_PRELOAD cannot
satisfy `dlopen@GLIBC_2.34 from libc.so.6`.

**Fix (two parts):**
1. Call `patch-glibc-versions.py` on `libepoxy.so.0.0.0` before staging in
   `build-rpms-native.sh` (it was being skipped while all other libs were patched).
2. Add `dlopen/dlsym/dlerror@GLIBC_2.34` wrappers to `libglibc-compat.so` via
   `.symver` assembler directives, with a `GLIBC_2.34` section in
   `libglibc-compat.map`, and build with `--version-script` + `-ldl`.

---

### Issue 21 — WPEInjectedBundle not found: hardcoded compile-time prefix

**Where:** `build-rpms-native.sh` wpewebkit2 staging; WPEWebProcess at runtime  
**Problem:** WPEWebKit is compiled with `--prefix /opt/wpe-sfos`, so
`WPEWebProcess` has `/opt/wpe-sfos/lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so`
hardcoded. The build script only staged the bundle to `/usr/lib64/wpe-webkit-2.0/`
(without the `injected-bundle/` sub-directory). Runtime error:
```
Error loading the injected bundle (/opt/wpe-sfos/...): No such file or directory
```
**Fix:** Stage the bundle to both paths:
```bash
mkdir -p "${S}/opt/wpe-sfos/lib/wpe-webkit-2.0/injected-bundle"
cp libWPEInjectedBundle.so "${S}/opt/wpe-sfos/lib/wpe-webkit-2.0/injected-bundle/"
cp libWPEInjectedBundle.so "${S}/usr/lib64/wpe-webkit-2.0/"
```
> **Note:** `WPE_PREFIX` at compile time must match the runtime install prefix, or
> the injected bundle path must be overridden via an environment variable before
> shipping.

---

## Architecture Overview

```
sailfish-browser (direct exec, no invoker/sailjail)
  └── BrowserPage.qml            ← Silica UI, unchanged
        └── WPEWebContainer      ← C++ QQuickItem, in libsailfishbrowser.so
              └── WPEWebPage     ← wraps WPEQtView (libqtwpe.so)
                    └── libWPEWebKit-2.0.so
                          ├── WebProcess  (spawned via execve)
                          └── NetworkProcess (spawned via execve)
```

The `libexecve_wrap*.so` shims intercept the `execve()` calls that launch
WebProcess and NetworkProcess, rewriting their library paths to point at
`~/wpe-sfos-artifacts/lib` before `exec` hands off to the kernel.

---

## Building Distributable RPMs

All spec files are in `rpm/`. Use the Sailfish SDK CLI (`sfdk`) with the
SFOS 5.0.0.62 aarch64 target.

### 1. Stage sources

Run the provided script once to download and archive all source tarballs into
`~/rpmbuild/SOURCES/`:

```bash
bash setup-rpmbuild.sh
```

This will:
- Create `wpe-sfos-compat-1.0.0.tar.bz2` from the current git repo
- Clone and archive libwpe 1.17.0, libepoxy 1.5.11, WPEBackend-fdo 1.17.0
- Download `wpewebkit-2.50.5.tar.xz` from wpewebkit.org
- Copy toolchain files, patches, and scripts

### 2. Configure sfdk target

```bash
sfdk config target=SailfishOS-5.0.0.62-aarch64
```

### 3. Build in order

Each package must be built and installed into the SDK target before the next:

```bash
sfdk build rpm/libwpe.spec
sfdk build rpm/libepoxy.spec
sfdk build rpm/wpebackend-fdo.spec
sfdk build rpm/wpe-sfos-compat.spec
sfdk build rpm/wpewebkit2.spec
sfdk build rpm/wpewebkit2-qt5.spec
# From the sailfish-browser repo:
sfdk build rpm/sailfish-browser.spec
```

> ⚠️ `wpewebkit2` takes 60–90 min to build on an 8-core machine.

### 4. Install to device

```bash
scp RPMS/aarch64/*.rpm nemo@device:~/
ssh nemo@device 'devel-su rpm -Uvh ~/*.rpm'
```

---

## Contributing

This port targets upstreaming. Patches should be:

1. **Minimal** — change only what SFOS requires, keep as close to upstream WPE/WebKit as possible.
2. **Documented** — explain *why* SFOS needs the workaround (glibc version, missing instruction, etc.).
3. **Upstream-ready** — shims and patches should be written in a form that can be submitted to the relevant upstream project.

Open issues and PRs are welcome.
