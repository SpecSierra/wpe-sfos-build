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
| `deploy/` | helper-process wrappers and deployment-time assets |
| `native-meson.ini` | native meson config for engine-side dependencies |
| `sfos-toolchain.cmake` | SFOS sysroot toolchain for Qt/UI builds |
| `patches and shim sources` | compatibility work carried from the old line |

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

That last point is intentional: isolation work is out of the default path for this migration
unless it becomes a release requirement again later.

## Legacy compatibility inventory

This is the current keep/drop inventory for the old SFOS 5.0 compatibility stack.

| Item | Status | Why |
| --- | --- | --- |
| `libglibc-compat.so` | `remove` on SFOS 5.1 if ABI confirms cleanly | old line only needed this for glibc 2.30 gaps |
| `patch-glibc-versions.py` | `remove` on SFOS 5.1 unless a specific binary still needs it | should not stay in the normal path if the new baseline already matches runtime glibc |
| `libglib-compat.so` | `remove` on SFOS 5.1 if GLib ABI is sufficient | carried for older GLib behavior on the SFOS 5.0 line |
| `libcow_string_compat.so` | `re-check` | may disappear with the 5.1 rebuild, but needs confirmation against the rebuilt runtime |
| `libsigill_skip*.so` | `re-check` | only keep if the rebuilt 5.1 line still trips unsupported CPU feature probes |
| `libgetauxval_fix*.so` | `re-check` | legacy workaround; verify before carrying forward |
| `libexecve_wrap*.so` | `remove` | tied to the older wrapped process-launch path and sailjail-era assumptions |
| broad `LD_PRELOAD` stacks | `remove` | migration goal is a minimal runtime closure, not global preload repair |
| `libegl-stubs.so` | `keep temporarily` | still potentially relevant if Sailfish/hybris EGL remains short on required symbols |
| `libepoxy-rtld-default-fallback.patch` | `keep temporarily` | coupled to `libegl-stubs.so`; re-check once the 5.1 runtime is exercised |
| `BubblewrapLauncher-sfos-sandbox.patch` | `remove from default path` | no longer part of the main migration direction |
| sailjail-disabled packaging/profile workarounds | `re-check` | keep only if they are still required to launch the app cleanly on 5.1 |

## Current local patch queue

These are the repo-local patches currently relevant to the live build flow.

| Patch | Status | Notes |
| --- | --- | --- |
| `libepoxy-rtld-default-fallback.patch` | `keep temporarily` | currently applied in the engine build so `libegl-stubs.so` can satisfy missing EGL symbols on Sailfish/hybris |
| `webkit-quirks-no-video.patch` | `re-check` | only relevant while the scripted baseline still builds WebKit with `ENABLE_VIDEO=OFF` |
| `webkit-icu-imported-targets.patch` | `keep temporarily` | fixes the 2.52.3 configure path on Ubuntu 24.04 by repairing the `ICU::` imported targets after `find_package(ICU ...)` |
| `qt5-plugin-gnuinstalldirs.patch` | `reference only` | the current `wpewebkit-2.52.1` Qt5 carry-forward snapshot already contains this install-path fix, so it is no longer re-applied in the default path |
| `qt5-plugin-epoxy-gl-fix.patch` | `reference only` | the current `wpewebkit-2.52.1` Qt5 carry-forward snapshot already contains this header/include fix |
| `wpeqtview-carryforward.patch` | `reference only` | records the SFOS API additions, deferred device scale, and Qt 5.6 touch guard already carried by the `wpewebkit-2.52.1` Qt5 source snapshot |
| `BubblewrapLauncher-sfos-sandbox.patch` | `drop from default path` | historical SFOS 5.0 isolation workaround; no longer part of the main build flow |

## Practical next steps

The next useful repo changes should be:

1. Build and validate the default **SFOS 5.1.0.5 / WPE 2.52.3** line end to end.
2. Re-check the remaining explicit shims (`libcow_string_compat.so`, `libsigill_skip.so`, `libegl-stubs.so`) against real runtime behavior.
3. Make fresh install match the staged tree exactly, with no manual device-side fixes.
4. Align or retire the older `setup-rpmbuild.sh` / `rpm/*.spec` path once the scripted baseline is fully proven.

## Build philosophy

Atlantic should be maintained like a browser port:

- engine updates should be routine
- local patches should stay named and small
- runtime layout should be explicit
- the UI should remain thin while the engine moves forward

If a change makes the next engine bump easier, it is probably the right change.
