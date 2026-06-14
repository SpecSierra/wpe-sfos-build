#!/bin/bash

readonly ENGINE_SOURCE_PATCHES=(
    "patches/engine/libepoxy-rtld-default-fallback.patch"
)

readonly WEBKIT_SOURCE_PATCHES=(
    "patches/webkit/webkit-quirks-no-video.patch"
    "patches/webkit/webkit-icu-imported-targets.patch"
    "patches/webkit/webkit-ramsize-cstddef.patch"
    "patches/webkit/webkit-wtf-header-includes.patch"
    "patches/webkit/webkit-wtf-platform-stdint.patch"
    "patches/webkit/webkit-wtf-glib-platform.patch"
    "patches/webkit/webkit-wtf-glib-header-includes.patch"
    "patches/webkit/webkit-wtf-linux-header-includes.patch"
    "patches/webkit/webkit-wtf-posix-unix-platform.patch"
    "patches/webkit/webkit-memoryfootprint-cstddef.patch"
    "patches/webkit/webkit-unistdextras-includes.patch"
    "patches/webkit/webkit-pal-system-header-includes.patch"
    "patches/webkit/webkit-pal-text-header-includes.patch"
    "patches/webkit/webkit-pal-header-owners.patch"
    "patches/webkit/webkit-jsc-glib-export-macros.patch"
    "patches/webkit/webkit-jsc-assembler-platform.patch"
    "patches/webkit/webkit-jsc-cpu-b3-includes.patch"
    "patches/webkit/webkit-jsc-b3-export-macros.patch"
    "patches/webkit/webkit-jsc-b3-platform.patch"
    "patches/webkit/webkit-jsc-b3-cstdint.patch"
    "patches/webkit/webkit-jsc-bytecode-platform.patch"
    "patches/webkit/webkit-jsc-dfg-platform.patch"
    "patches/webkit/webkit-jsc-ftl-platform.patch"
    "patches/webkit/webkit-jsc-heap-cstddef.patch"
    "patches/webkit/webkit-jsc-inspector-remote-glib.patch"
    "patches/webkit/webkit-jsc-jit-platform.patch"
    "patches/webkit/webkit-jsc-lol-platform.patch"
    "patches/webkit/webkit-jsc-wasm-platform.patch"
    "patches/webkit/webkit-jsc-llint-build-defines.patch"
    "patches/webkit/webkit-jsc-shell-object-link.patch"
    "patches/webkit/webkit-webcore-user-message-handlers-platform.patch"
    "patches/webkit/webkit-webcore-colorconversion-export-macros.patch"
    "patches/webkit/webkit-webcore-webkitnamespace-platform.patch"
    "patches/webkit/webkit-webcore-avif-platform.patch"
    "patches/webkit/webkit-webcore-avif-reader-platform.patch"
    "patches/webkit/webkit-webcore-context-export-macros.patch"
    "patches/webkit/webkit-webcore-bitmaptexturepool-owners.patch"
    "patches/webkit/webkit-webcore-texmap-owner-headers.patch"
    "patches/webkit/webkit-glfence-disable-env.patch"
    "patches/webkit/webkit-texpool-compositor-sync-env.patch"
    "patches/webkit/webkit-raster-on-compositor-thread-env.patch"
    "patches/webkit/webkit-directional-tile-coverage-env.patch"
    # webkit-touch-async-scroll-env.patch: touch/touchpad (precise-delta) panning
    # scrolls on the async scrolling thread even over a non-passive wheel region,
    # instead of being forced synchronous on the main thread (the keystone that
    # kept WPE's already-enabled APZ from engaging on SPAs like reddit — see the
    # patch header). Restores off-main-thread scrolling + kinetic momentum.
    # Toggle off with WEBKIT_TOUCH_SCROLL_ASYNC=0.
    "patches/webkit/webkit-touch-async-scroll-env.patch"
    "patches/webkit/webkit-renderbox-isnan.patch"
    "patches/webkit/webkit-shapeoutside-isnan.patch"
    # webkit-gpu-process-by-default-wpe.patch: DISABLED. It hard-enables
    # ENABLE_GPU_PROCESS_DOM_RENDERING_BY_DEFAULT, moving DOM rendering into the
    # GPU process. On this libhybris/Adreno device there is no GBM / DRM render
    # node, so the GPU process cannot export composited frames — pages render
    # blank (chrome draws, content area white). Verified on-device (Xperia 10 II).
    # Keep DOM rendering in the WebProcess (the path that exports via WPEBackend-fdo).
    # The patch file is kept in patches/webkit/ for reference / future hybris
    # GPU-export work. See also webkit-gpu-process-egl-default-display-fallback.
    # "patches/webkit/webkit-gpu-process-by-default-wpe.patch"
    "patches/webkit/webkit-gpu-process-egl-default-display-fallback.patch"
    "patches/webkit/webkit-jsc-linux-arm64-thread-tuning.patch"
    "patches/webkit/webkit-jsc-linux-arm64-jit-thresholds.patch"
    "patches/webkit/webkit-webcore-scroll-anim-narrowing.patch"
    # webkit-gst-buffer-tuning.patch: makes GstQueue2 high-watermark,
    # urisourcebin ring-buffer-max-size and uridecodebin buffer-size
    # configurable via WEBKIT_GST_QUEUE_HIGH_WATERMARK /
    # WEBKIT_GST_RING_BUFFER_MAX_SIZE / WEBKIT_GST_URIDECODEBIN_BUFFER_SIZE
    # (defaults exported by deploy/runtime-common.sh). Authored in 20106a4 but
    # never added to this list — the runtime env vars were dead until now.
    "patches/webkit/webkit-gst-buffer-tuning.patch"
    "patches/webkit/webkit-bubblewrap-sfos-sandbox.patch"
    # TEMP diagnostic — REMOVE after root-causing touch async scroll. Logs the
    # WebProcess wheel-event scrolling decision to /tmp/wpe-scroll-diag.log.
    "patches/webkit/zz-diag-wheel-logging.patch"
)

readonly QT5_PLUGIN_PATCHES=(
    # Empty on purpose: all historical qt5-plugin patches are baked into the
    # self-contained qt5-plugin/ source directory (the patch files have been
    # removed — see git history for the individual changes).
)

apply_single_repo_patch() {
    local strip_level="$1"
    local target_dir="$2"
    local patch_file="$3"
    local patch_path="${BUILD_TOOLS}/${patch_file}"

    if [ ! -f "${patch_path}" ]; then
        echo "ERROR: missing patch ${patch_path}" >&2
        return 1
    fi

    echo "  Applying ${patch_file}"

    if (
        cd "${target_dir}" &&
        patch "-p${strip_level}" --batch --forward --dry-run < "${patch_path}" >/dev/null 2>&1
    ); then
        (
            cd "${target_dir}" &&
            patch "-p${strip_level}" --batch --forward < "${patch_path}"
        )
        return $?
    fi

    if (
        cd "${target_dir}" &&
        patch "-p${strip_level}" --batch --reverse --dry-run < "${patch_path}" >/dev/null 2>&1
    ); then
        echo "    ${patch_file} already present; skipping"
        return 0
    fi

    echo "ERROR: failed to apply ${patch_file} in ${target_dir}" >&2
    return 1
}

apply_repo_patches() {
    local strip_level="$1"
    local target_dir="$2"
    shift 2

    local patch_file
    for patch_file in "$@"; do
        apply_single_repo_patch "${strip_level}" "${target_dir}" "${patch_file}" || return 1
    done
}
