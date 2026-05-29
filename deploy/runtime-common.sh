#!/bin/sh

ATLANTIC_RUNTIME_PREFIX="${ATLANTIC_RUNTIME_PREFIX:-/opt/wpe-sfos}"
ATLANTIC_RUNTIME_LIBDIR="${ATLANTIC_RUNTIME_LIBDIR:-/usr/lib64}"
ATLANTIC_COMPAT_DIR="${ATLANTIC_COMPAT_DIR:-${ATLANTIC_RUNTIME_LIBDIR}/wpe-compat}"
ATLANTIC_WPE_HELPER_DIR="${ATLANTIC_WPE_HELPER_DIR:-/usr/libexec/wpe-webkit-2.0}"
ATLANTIC_QT_QPA_PLATFORM="${ATLANTIC_QT_QPA_PLATFORM:-wayland}"
ATLANTIC_XDG_RUNTIME_DIR="${ATLANTIC_XDG_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/run/user/100000}}"
ATLANTIC_WAYLAND_DISPLAY="${ATLANTIC_WAYLAND_DISPLAY:-../../display/wayland-0}"
ATLANTIC_GSTREAMER_PLUGIN_DIR="${ATLANTIC_GSTREAMER_PLUGIN_DIR:-${ATLANTIC_RUNTIME_LIBDIR}/gstreamer-1.0}"
ATLANTIC_GST_PLUGIN_FEATURE_RANK="${ATLANTIC_GST_PLUGIN_FEATURE_RANK:-droidvdec:0,droidvenc:0}"
ATLANTIC_WEBKIT_HLS_SUPPORT="${ATLANTIC_WEBKIT_HLS_SUPPORT:-1}"
ATLANTIC_BROWSER_RUNTIME_DELAY_MS="${ATLANTIC_BROWSER_RUNTIME_DELAY_MS:-2000}"

atlantic_default_pulse_server() {
    for pulse_socket in \
        "${ATLANTIC_XDG_RUNTIME_DIR}/pulse/native" \
        "/run/pulse/native"
    do
        if [ -S "${pulse_socket}" ]; then
            printf 'unix:%s' "${pulse_socket}"
            return
        fi
    done
}

atlantic_build_ld_preload() {
    preload=""
    sep=""

    if [ "${USE_GLIBC_COMPAT:-0}" = "1" ]; then
        preload="${preload}${sep}${ATLANTIC_COMPAT_DIR}/libglibc-compat.so"
        sep=":"
    fi
    if [ "${USE_COW_STRING_COMPAT:-0}" = "1" ]; then
        preload="${preload}${sep}${ATLANTIC_COMPAT_DIR}/libcow_string_compat.so"
        sep=":"
    fi
    if [ "${USE_SIGILL_SKIP:-0}" = "1" ]; then
        preload="${preload}${sep}${ATLANTIC_COMPAT_DIR}/libsigill_skip.so"
        sep=":"
    fi
    if [ "${USE_GLIB_COMPAT:-0}" = "1" ]; then
        preload="${preload}${sep}${ATLANTIC_COMPAT_DIR}/libglib-compat.so"
        sep=":"
    fi
    if [ "${USE_EGL_STUBS:-0}" = "1" ]; then
        preload="${preload}${sep}${ATLANTIC_COMPAT_DIR}/libegl-stubs.so"
    fi

    printf '%s' "${preload}"
}

atlantic_default_library_path() {
    printf '%s:%s' "${ATLANTIC_COMPAT_DIR}" "${ATLANTIC_RUNTIME_LIBDIR}"
}

atlantic_default_helper_library_path() {
    printf '%s:%s' "$(atlantic_default_library_path)" "${ATLANTIC_RUNTIME_PREFIX}/lib"
}

atlantic_export_helper_env() {
    if [ -n "${ATLANTIC_LD_PRELOAD:-}" ]; then
        export LD_PRELOAD="${ATLANTIC_LD_PRELOAD}"
    else
        unset LD_PRELOAD 2>/dev/null || true
    fi

    export LD_LIBRARY_PATH="${ATLANTIC_LD_LIBRARY_PATH:-$(atlantic_default_helper_library_path)}"
    export XDG_RUNTIME_DIR="${ATLANTIC_XDG_RUNTIME_DIR}"
    export WAYLAND_DISPLAY="${ATLANTIC_WAYLAND_DISPLAY}"
    if [ -z "${PULSE_SERVER:-}" ]; then
        pulse_server="$(atlantic_default_pulse_server)"
        if [ -n "${pulse_server}" ]; then
            export PULSE_SERVER="${pulse_server}"
        fi
    fi
    export GST_PLUGIN_SYSTEM_PATH_1_0="${ATLANTIC_GSTREAMER_PLUGIN_DIR}"
    export GST_PLUGIN_PATH="${ATLANTIC_GSTREAMER_PLUGIN_DIR}"
    export GST_PLUGIN_FEATURE_RANK="${ATLANTIC_GST_PLUGIN_FEATURE_RANK}"
}

atlantic_export_browser_env() {
    atlantic_export_helper_env
    export QT_QPA_PLATFORM="${ATLANTIC_QT_QPA_PLATFORM}"
    export QSG_RENDER_LOOP="${QSG_RENDER_LOOP:-threaded}"
    export ATLANTIC_BROWSER_RUNTIME_DELAY_MS="${ATLANTIC_BROWSER_RUNTIME_DELAY_MS}"
    export WEBKIT_GST_ENABLE_HLS_SUPPORT="${ATLANTIC_WEBKIT_HLS_SUPPORT}"

    # ── JSC JIT thread tuning (Snapdragon 665: 8-core big.LITTLE) ────────────
    # Default JSC spawns 7 FTL threads + 8 GC markers on an 8-core device,
    # flooding the CPU during page load.  Cap to sane mobile limits.
    export JSC_numberOfFTLCompilerThreads="${JSC_numberOfFTLCompilerThreads:-2}"
    export JSC_numberOfDFGCompilerThreads="${JSC_numberOfDFGCompilerThreads:-2}"
    export JSC_numberOfBaselineCompilerThreads="${JSC_numberOfBaselineCompilerThreads:-2}"
    export JSC_numberOfGCMarkers="${JSC_numberOfGCMarkers:-4}"
    export JSC_maxNumberOfWorklistThreads="${JSC_maxNumberOfWorklistThreads:-4}"
    export JSC_worklistLoadFactor="${JSC_worklistLoadFactor:-20}"
    export JSC_worklistFTLLoadWeight="${JSC_worklistFTLLoadWeight:-20}"
    export JSC_worklistDFGLoadWeight="${JSC_worklistDFGLoadWeight:-5}"
    export JSC_worklistBaselineLoadWeight="${JSC_worklistBaselineLoadWeight:-2}"

    # ── JSC JIT tier-up thresholds ────────────────────────────────────────────
    # Lower thresholds so hot functions reach JIT earlier without waiting for
    # the default call-count watermarks (500/1000).
    export JSC_thresholdForJITAfterWarmUp="${JSC_thresholdForJITAfterWarmUp:-100}"
    export JSC_thresholdForOptimizeAfterWarmUp="${JSC_thresholdForOptimizeAfterWarmUp:-500}"

    # ── JSC GC heap tuning ────────────────────────────────────────────────────
    # Cap JS heap at 35% of available RAM. Setting 0.8/0.9 let the heap grow
    # to ~900 MB before GC, pushing this device into heavy zram swap (884/1024 MB
    # used) — swap latency is far worse than GC churn. 35% ≈ 350 MB for JS
    # on this 3.5 GB device, enough for large SPAs without thrashing swap.
    export JSC_smallHeapRAMFraction="${JSC_smallHeapRAMFraction:-0.35}"
    export JSC_largeHeapRAMFraction="${JSC_largeHeapRAMFraction:-0.35}"
    export JSC_largeHeapSize="${JSC_largeHeapSize:-67108864}"

    # ── Skia painting thread caps (Adreno 610: single GPU command queue) ──────
    export WEBKIT_SKIA_GPU_PAINTING_THREADS="${WEBKIT_SKIA_GPU_PAINTING_THREADS:-2}"
    export WEBKIT_SKIA_CPU_PAINTING_THREADS="${WEBKIT_SKIA_CPU_PAINTING_THREADS:-2}"

    # ── Tile size alignment ───────────────────────────────────────────────────
    # Align tiles to 512 px to halve texture uploads vs default 256 px.
    export WEBKIT_LAYERS_TILE_SIZE="${WEBKIT_LAYERS_TILE_SIZE:-512}"
}

atlantic_cleanup_runtime_artifacts() {
    rm -rf "${ATLANTIC_XDG_RUNTIME_DIR}/.flatpak"/webkit-* \
           "${ATLANTIC_XDG_RUNTIME_DIR}/wpe"/bus-proxy-* 2>/dev/null || true
}
