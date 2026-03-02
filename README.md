# wpe-sfos-build

Compatibility shims, cross-compilation toolchain, and build tooling for running
**WPE WebKit 2.50.5** on **Sailfish OS 5.0 (aarch64)**.

This repo is the glue layer between stock WPE WebKit and the constraints of SFOS:
older glibc (2.28), limited CPU instruction set (ARMv8.0-A), and the sailjail
sandbox. It accompanies the browser source at
[SpecSierra/sailfish-browser](https://github.com/SpecSierra/sailfish-browser).

---

## Target Device

| | |
|---|---|
| Device | Sony Xperia 10 II |
| SoC | Snapdragon 665 (Cortex-A53/A55, ARMv8.0-A) |
| OS | Sailfish OS 5.0.0.62 |
| Arch | aarch64 |
| glibc | 2.28 |
| Qt | 5.6.3 (system) |

---

## Repository Contents

| File | Purpose |
|---|---|
| `sfos-toolchain.cmake` | CMake cross-compilation toolchain |
| `sfos-meson-cross.ini` | Meson cross-file (for libwpe / WPEBackend-fdo) |
| `libglibc-compat.c` | Shim: provide glibc 2.29+ symbols missing from SFOS glibc 2.28 |
| `libgetauxval_fix.c` | Shim: fix `getauxval(AT_HWCAP2/AT_MINSIGSTKSZ)` on SFOS aarch64 |
| `libgetauxval_fix2.c` | Variant of the above for the WebProcess/NetworkProcess helpers |
| `libsigill_skip.c` | Shim: skip SIGILL-triggering CPU feature probes (ARMv8.1+ instructions) |
| `libsigill_skip2.c` | Variant for libWPEBackend-fdo feature probes |
| `libsigill_skip3.c` | Variant for libwpe feature probes |
| `libexecve_wrap.c` | Shim: rewrite `execve()` paths for WebProcess under sailjail |
| `libexecve_wrap2.c` | Variant for NetworkProcess |
| `libegl-stubs.c` | Stub missing EGL entry points that libepoxy probes at load time |
| `make_wpe_wrapper.c` | Generates the `wpe-browser` launcher with correct `LD_PRELOAD` order |
| `patch-glibc-versions.py` | Post-link: rewrite `GLIBC_2.3x` ELF version tags → `GLIBC_2.28` |
| `easylist-to-webkit.py` | Convert EasyList/uBlock filter lists to WebKit content blocker JSON |
| `webkit-quirks-no-video.patch` | WebKit `Quirks.cpp` patch: guard `HTMLVideoElement` refs with `#if ENABLE(VIDEO)` |

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
PKG_CONFIG_PATH=/opt/wpe-sfos/lib/pkgconfig \
meson setup build \
    --cross-file /path/to/wpe-sfos-build/sfos-meson-cross.ini \
    --prefix /opt/wpe-sfos \
    --buildtype release
PKG_CONFIG_PATH=/opt/wpe-sfos/lib/pkgconfig ninja -C build install
```

### 4. WPE WebKit 2.50.5

Download the release tarball (not the full WebKit git tree — it is 10+ GB):

```bash
wget https://wpewebkit.org/release/wpewebkit-2.50.5.tar.xz
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
```

> ⚠️ WPE WebKit is a large build. Expect 60–90 minutes on an 8-core machine.

#### Qt5 WPE Plugin (libqtwpe.so)

The Qt5 WPE plugin source lives inside the WPE WebKit tarball at
`Source/WebKit/UIProcess/API/wpe/qt5/`. Build it separately with Qt 5.6:

```bash
# qmake is inside the SFOS sysroot — add it to PATH first
export PATH="/opt/sfos-sysroot/usr/lib64/qt5/bin:$PATH"

cd wpewebkit-2.50.5/Source/WebKit/UIProcess/API/wpe/qt5
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

> **Note:** The top-level `sailfish-browser.pro` includes `settings/` and
> `backup-unit/` sub-projects that may fail if optional SFOS packages
> (`vault`, etc.) are absent from the sysroot. These sub-projects are not
> needed for the browser to run — build only the core library and binary if
> the top-level make fails:
> ```bash
> make -C apps/lib
> make -C apps/browser
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
| sailjail / invoker disabled | 🔴 Workaround | Sailjail firejail profile does not yet include WPE library paths. Disable with `/etc/sailjail/config/50-enable-sandboxing.conf` → `Enabled=false` |
| GStreamer / video playback | 🔴 Not implemented | WPE built with `ENABLE_VIDEO=OFF`. Static GStreamer stub (`libgst-static-stub.so`) prevents crashes |
| File downloads | 🔴 Not implemented | `webkit_download_*` API hookup planned |
| ARMv8.1+ instruction probes | ✅ Mitigated | `libsigill_skip*.so` shims handle `SIGILL` from CPU feature detection |
| glibc 2.29+ symbols | ✅ Mitigated | `libglibc-compat.so` + `patch-glibc-versions.py` |
| JPEG ABI mismatch | ✅ Fixed | `libjpeg_safe.so` intercepts libjpeg calls |

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

## Contributing

This port targets upstreaming. Patches should be:

1. **Minimal** — change only what SFOS requires, keep as close to upstream WPE/WebKit as possible.
2. **Documented** — explain *why* SFOS needs the workaround (glibc version, missing instruction, etc.).
3. **Upstream-ready** — shims and patches should be written in a form that can be submitted to the relevant upstream project.

Open issues and PRs are welcome.
