# wpe-sfos-build

Build, packaging, and compatibility work for **Atlantic Browser** on **Sailfish OS**.

## Status

This repo is now being used to move Atlantic onto a cleaner baseline:

- **Target OS:** Sailfish OS **5.1.0.5**
- **Target engine:** WPE WebKit **2.52.3**
- **Priority:** smaller patch queue, simpler packaging, faster engine updates
- **Not a priority right now:** `bubblewrap`, `sailjail`, or growing the old preload stack

The live scripts in this repo now default to the **SFOS 5.1.0.5 / WPE 2.52.3**
line. The older **WPE 2.52.1** line is still available by explicit override while
the Qt5 bridge continues to be carried forward from the existing **2.52.1** source
snapshot. Those pins are explicit in `versions.env` so the remaining runtime work
can happen deliberately instead of chasing hard-coded versions scattered through the
scripts.

The repo-side validation baseline is now stronger than it was on the old line:

- the engine, WebKit, Qt5 bridge, and Atlantic UI all build cleanly against a fresh **2.52.3** temp prefix
- the native RPM path can package that validated temp prefix directly without hard-coded soname drift
- `setup-rpmbuild.sh` and the WebKit RPM specs now stage the **2.52.3** engine source plus the explicit **2.52.1** Qt5 carry-forward snapshot

## Live workspace

Current checkouts on the build host:

| Path | Role |
| --- | --- |
| `/release/workspace/wpe-sfos-build` | engine build, packaging, compatibility cleanup |
| `/release/workspace/sailfish-browser-wpe` | Atlantic browser UI/application |

## Repo layout

| File | Purpose |
| --- | --- |
| `versions.env` | central version pins for the current scripted baseline and the migration target |
| `build-all.sh` | top-level orchestrator over the split build entrypoints |
| `scripts/bootstrap-host.sh` | host dependencies, sysroot setup, and workspace bootstrap |
| `scripts/build-engine.sh` | engine dependency build (`libwpe`, `libepoxy`, `WPEBackend-fdo`) |
| `scripts/build-webkit.sh` | WPE WebKit build, legacy Qt5 bridge carry-forward, and GLIBC patching |
| `scripts/build-ui.sh` | Atlantic UI/browser build against the staged engine |
| `scripts/package-rpms.sh` | packaging entrypoint that delegates to the native RPM staging script |
| `build-rpms-native.sh` | native RPM staging/packaging script |
| `cmake/` | shared CMake cache presets used by both the script and spec packaging paths |
| `deploy/` | helper-process wrappers, shared runtime env, and deployment-time assets |
| `native-meson.ini` | native meson config for engine-side dependencies |
| `sfos-toolchain.cmake` | SFOS sysroot toolchain for Qt/UI builds |
| `patches/` | repo-local engine, WebKit, Qt bridge, and historical patches grouped by area |
| `shims/compat/` | C shim sources and linker maps for the remaining compatibility package/workarounds |

## Version pins

The important pins now live in `versions.env`.

### Current scripted baseline

| Item | Version |
| --- | --- |
| SFOS sysroot | `5.1.0.5` |
| libwpe | `1.17.0` |
| libepoxy | `1.5.11` |
| WPEBackend-fdo | `1.17.0` |
| WPE WebKit | `2.52.3` |
| Qt5 plugin source fallback | `2.52.1` |

### Migration target

| Item | Version |
| --- | --- |
| SFOS baseline | `5.1.0.5` |
| WPE WebKit | `2.52.3` |

## Current script behavior

`build-all.sh` and `build-rpms-native.sh` now expose a real split between bootstrap,
engine, WebKit, UI, and packaging entrypoints. The current cleanup pass does six
important things:

1. Removes hard-coded version drift by sourcing `versions.env`.
2. Fixes the missing `WPE_SOURCE_DIR` wiring in `build-all.sh`.
3. Stops packaging and depending on `bubblewrap` even though the current WPE build already sets `-DENABLE_BUBBLEWRAP_SANDBOX=OFF`.
4. Drops `libglibc-compat.so`, `libglib-compat.so`, and default GLIBC retagging from the normal **SFOS 5.1.0.5** path while keeping the still-uncertain shims explicit.
5. Makes the build flow easier to rework incrementally for the SFOS 5.1.0.5 / WPE 2.52.3 line without editing one rescue-style script.
6. Makes the Qt5 bridge carry-forward explicit by sourcing it from the existing `wpewebkit-2.52.1` snapshot instead of pretending a clean `2.50.5` tarball is sufficient on its own.

Recent validation tightened the live flow further:

1. `scripts/build-ui.sh` now drives the qmake-generated `apps/` subproject correctly and builds only the Atlantic browser targets instead of tripping over unrelated subapps.
2. `build-rpms-native.sh` now stages shared-library families dynamically, avoids mutating the source prefix in place, and can package from an alternate validated prefix while keeping the runtime `/opt/wpe-sfos` paths explicit.
3. `setup-rpmbuild.sh`, `rpm/wpewebkit2.spec`, and `rpm/wpewebkit2-qt5.spec` now reflect the real **2.52.3 + 2.52.1 carry-forward** source layout instead of the stale **2.50.5** assumptions.

That last point is intentional: isolation work is out of the default path for this migration
unless it becomes a release requirement again later.

## Legacy compatibility inventory

This is the current keep/drop inventory for the old SFOS 5.0 compatibility stack.

| Item | Status | Why |
| --- | --- | --- |
| `libglibc-compat.so` | `remove` on SFOS 5.1 if ABI confirms cleanly | old line only needed this for glibc 2.30 gaps |
| `patch-glibc-versions.py` | `remove` on SFOS 5.1 unless a specific binary still needs it | should not stay in the normal path if the new baseline already matches runtime glibc |
| `libglib-compat.so` | `remove` on SFOS 5.1 if GLib ABI is sufficient | carried for older GLib behavior on the SFOS 5.0 line |
| `libcow_string_compat.so` | `remove` on SFOS 5.1 | the rebuilt 5.1 runtime makes `invoker` fail on `__libc_single_threaded`, so this shim is no longer safe in the default path |
| `libsigill_skip.so` | `re-check` | only keep if the rebuilt 5.1 line still trips unsupported CPU feature probes |
| `libgetauxval_fix*.so` | `removed from default package` | legacy workaround no longer used by the current runtime closure |
| `libexecve_wrap*.so` | `removed from default package` | tied to the older wrapped process-launch path and sailjail-era assumptions |
| broad `LD_PRELOAD` stacks | `remove` | migration goal is a minimal runtime closure, not global preload repair |
| `libegl-stubs.so` | `keep temporarily` | still potentially relevant if Sailfish/hybris EGL remains short on required symbols |
| `patches/engine/libepoxy-rtld-default-fallback.patch` | `keep temporarily` | coupled to `libegl-stubs.so`; re-check once the 5.1 runtime is exercised |
| `patches/historical/BubblewrapLauncher-sfos-sandbox.patch` | `remove from default path` | no longer part of the main migration direction |
| sailjail-disabled packaging/profile workarounds | `re-check` | keep only if they are still required to launch the app cleanly on 5.1 |

## Current local patch queue

These are the repo-local patches currently relevant to the live build flow.

| Patch | Status | Notes |
| --- | --- | --- |
| `patches/engine/libepoxy-rtld-default-fallback.patch` | `keep temporarily` | currently applied in the engine build so `libegl-stubs.so` can satisfy missing EGL symbols on Sailfish/hybris |
| `patches/webkit/webkit-quirks-no-video.patch` | `re-check` | only relevant while the scripted baseline still builds WebKit with `ENABLE_VIDEO=OFF` |
| `patches/webkit/webkit-icu-imported-targets.patch` | `keep temporarily` | fixes the 2.52.3 configure path on Ubuntu 24.04 by repairing the `ICU::` imported targets after `find_package(ICU ...)` |
| `patches/webkit/webkit-ramsize-cstddef.patch` | `keep temporarily` | fixes the 2.52.3 WTF compile on Ubuntu 24.04 by adding the missing `<cstddef>` include for `size_t` in `RAMSize.h` |
| `patches/webkit/webkit-wtf-header-includes.patch` | `keep temporarily` | fixes newer WTF header self-sufficiency issues on Ubuntu 24.04 by adding missing `<cstdint>` and `Assertions.h` includes for `EnumTraits.h` and `TypeCasts.h` |
| `patches/webkit/webkit-wtf-platform-stdint.patch` | `keep temporarily` | fixes additional WTF 2.52.3 portability/self-sufficiency issues by importing `Platform.h` anywhere new Android WTF files use `OS(ANDROID)` and `<cstdint>` where `uint8_t` is used in `UTF8Conversion.h` |
| `patches/webkit/webkit-wtf-glib-platform.patch` | `keep temporarily` | fixes the same self-sufficient header problem across the new WTF GLib files by importing `Platform.h` wherever `USE(GLIB)`, `PLATFORM(WPE)`, or `OS(...)` guards are used directly |
| `patches/webkit/webkit-wtf-glib-header-includes.patch` | `keep temporarily` | fixes the next GLib WTF self-sufficiency layer by importing the headers that own `WTF_EXPORT_PRIVATE` and `WTF_MAKE_TZONE_ALLOCATED` in the new GLib headers |
| `patches/webkit/webkit-wtf-linux-header-includes.patch` | `keep temporarily` | fixes the same self-sufficiency issue in the Linux WTF memory/thread headers by importing `Platform.h` and `ExportMacros.h` where `OS(...)` and `WTF_EXPORT_PRIVATE` are used directly |
| `patches/webkit/webkit-wtf-posix-unix-platform.patch` | `keep temporarily` | fixes the same `Platform.h` ownership problem in the WTF POSIX/Unix sources that use `OS(...)`, `PLATFORM(...)`, or `USE(...)` directly |
| `patches/webkit/webkit-memoryfootprint-cstddef.patch` | `keep temporarily` | fixes `MemoryFootprint.h` on Ubuntu 24.04 by adding the missing `<cstddef>` include for `size_t` |
| `patches/webkit/webkit-unistdextras-includes.patch` | `keep temporarily` | fixes `UniStdExtras.h` by importing the headers that own `WTF_EXPORT_PRIVATE` and `OS(...)` before the inline Unix helpers are declared |
| `patches/webkit/webkit-renderbox-isnan.patch` | `keep temporarily` | fixes the 2.52.3 WebCore compile on Ubuntu 24.04 by making `RenderBox.h` use `std::isnan` with an explicit `<cmath>` include |
| `patches/webkit/webkit-shapeoutside-isnan.patch` | `keep temporarily` | fixes the 2.52.3 WebCore shape-outside compile on Ubuntu 24.04 by making `ShapeOutsideInfo.cpp` use `std::isnan` with an explicit `<cmath>` include |
| `patches/qt-bridge/qt5-plugin-texture-cache.patch` | `keep temporarily` | avoids rebuilding the Qt scene-graph texture wrapper every frame in the carried-forward Qt5 bridge; measured improvements were strongest on Canvas2D/WebGL perf probes |
| `patches/qt-bridge/qt5-plugin-gnuinstalldirs.patch` | `reference only` | the current `wpewebkit-2.52.1` Qt5 carry-forward snapshot already contains this install-path fix, so it is no longer re-applied in the default path |
| `patches/qt-bridge/qt5-plugin-epoxy-gl-fix.patch` | `reference only` | the current `wpewebkit-2.52.1` Qt5 carry-forward snapshot already contains this header/include fix |
| `patches/qt-bridge/wpeqtview-carryforward.patch` | `reference only` | records the SFOS API additions, deferred device scale, and Qt 5.6 touch guard already carried by the `wpewebkit-2.52.1` Qt5 source snapshot |
| `patches/historical/BubblewrapLauncher-sfos-sandbox.patch` | `drop from default path` | historical SFOS 5.0 isolation workaround; no longer part of the main build flow |

## Practical next steps

The next useful repo changes should be:

1. Run device/runtime validation for the rebuilt **SFOS 5.1.0.5 / WPE 2.52.3** packages.
2. Re-check the remaining explicit shims (`libsigill_skip.so`, `libegl-stubs.so`) against real runtime behavior.
3. Make fresh install match the staged tree exactly, with no manual device-side fixes.
4. Decide whether the remaining older RPM specs beyond the WebKit pair should be aligned further or retired in favor of the native packaging path.

## GitHub Actions build automation

This repo now has a first self-hosted ARM64 workflow at
`.github/workflows/build-atlantic-packages.yml`.

- Trigger modes:
  - manual `workflow_dispatch`
  - automatic `push` builds on `master` when build/package inputs change
- Runner labels:
  - `self-hosted`
  - `Linux`
  - `ARM64`
  - `atlantic`
- Main CI wrapper:
  - `scripts/ci-build.sh`

The workflow intentionally builds in isolated CI paths instead of the live
development prefix, while still seeding the CI sysroot from the local updated
host sysroot when the raw 5.1 SDK target archive is not publicly downloadable:

- `CI_ROOT=/opt/github-runner/builds/<run-id>-<attempt>`
- `WPE_PREFIX=${CI_ROOT}/wpe-sfos-prefix`
- `OUT=${CI_ROOT}/wpe-sfos-rpms`
- `STAGING=${CI_ROOT}/wpe-sfos-stage`
- `PUBLIC_SFOS_BASE_VERSION=5.0.0.62`
- `LOCAL_SFOS_SOURCE_SYSROOT=/opt/sfos-sysroot`
- `QT5_PLUGIN_SOURCE_DIR=/release/workspace/wpewebkit-2.52.1`
- `NPROC=6`
- `SYSROOT=/opt/github-runner/cache/sfos-sysroot-5.1.0.5`

That keeps CI runs from clobbering the live `/opt/wpe-sfos` tree used for manual
device work on the host.

Artifacts uploaded from each run include:

- `artifacts/build.log`
- `artifacts/summary.txt`
- `artifacts/rpms/*.rpm`
- `artifacts/build-config/` when WebKit metadata is available

## Build philosophy

Atlantic should be maintained like a browser port:

- engine updates should be routine
- local patches should stay named and small
- runtime layout should be explicit
- the UI should remain thin while the engine moves forward

If a change makes the next engine bump easier, it is probably the right change.
