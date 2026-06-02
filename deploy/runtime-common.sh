#!/bin/sh

ATLANTIC_RUNTIME_PREFIX="${ATLANTIC_RUNTIME_PREFIX:-/opt/wpe-sfos}"
ATLANTIC_RUNTIME_LIBDIR="${ATLANTIC_RUNTIME_LIBDIR:-/usr/lib64}"
ATLANTIC_COMPAT_DIR="${ATLANTIC_COMPAT_DIR:-${ATLANTIC_RUNTIME_LIBDIR}/wpe-compat}"
ATLANTIC_WPE_HELPER_DIR="${ATLANTIC_WPE_HELPER_DIR:-/usr/libexec/wpe-webkit-2.0}"
ATLANTIC_QT_QPA_PLATFORM="${ATLANTIC_QT_QPA_PLATFORM:-wayland}"
ATLANTIC_XDG_RUNTIME_DIR="${ATLANTIC_XDG_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/run/user/100000}}"
ATLANTIC_WAYLAND_DISPLAY="${ATLANTIC_WAYLAND_DISPLAY:-../../display/wayland-0}"
ATLANTIC_GSTREAMER_PLUGIN_DIR="${ATLANTIC_GSTREAMER_PLUGIN_DIR:-${ATLANTIC_RUNTIME_LIBDIR}/gstreamer-1.0}"
# droidvdec:0 disables Android hybris hardware video decoder.
# On SFOS 5.0 this prevented crashes in the hybris EGL → GStreamer path.
# On SFOS 5.1 with a working hybris stack, set ATLANTIC_ENABLE_HW_DECODER=1 to re-enable.
if [ "${ATLANTIC_ENABLE_HW_DECODER:-0}" = "1" ]; then
    ATLANTIC_GST_PLUGIN_FEATURE_RANK="${ATLANTIC_GST_PLUGIN_FEATURE_RANK:-}"
else
    ATLANTIC_GST_PLUGIN_FEATURE_RANK="${ATLANTIC_GST_PLUGIN_FEATURE_RANK:-droidvdec:0,droidvenc:0}"
fi
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
    export WEBKIT_GST_BUFFER_SIZE="${WEBKIT_GST_BUFFER_SIZE:-10485760}"
    # GStreamer pipeline tuning (via patched WebKit source)
    export WEBKIT_GST_QUEUE_HIGH_WATERMARK="${WEBKIT_GST_QUEUE_HIGH_WATERMARK:-0.05}"
    export WEBKIT_GST_RING_BUFFER_MAX_SIZE="${WEBKIT_GST_RING_BUFFER_MAX_SIZE:-16777216}"
    export WEBKIT_GST_URIDECODEBIN_BUFFER_SIZE="${WEBKIT_GST_URIDECODEBIN_BUFFER_SIZE:-8388608}"
    export WPE_SHELL_MEDIA_DISK_CACHE_SIZE_BYTES="${WPE_SHELL_MEDIA_DISK_CACHE_SIZE_BYTES:-67108864}"
    # Identify audio streams to PulseAudio as x-maemo so SFOS media policy routes them correctly.
    # Note: dot-containing property names must be set via PULSE_PROP_OVERRIDE (not PULSE_PROP_x.y).
    export PULSE_PROP_OVERRIDE="media.role=x-maemo"
}

atlantic_export_browser_env() {
    atlantic_export_helper_env
    export QT_QPA_PLATFORM="${ATLANTIC_QT_QPA_PLATFORM}"
    export QSG_RENDER_LOOP="${QSG_RENDER_LOOP:-threaded}"
    export ATLANTIC_BROWSER_RUNTIME_DELAY_MS="${ATLANTIC_BROWSER_RUNTIME_DELAY_MS}"
    export WEBKIT_GST_ENABLE_HLS_SUPPORT="${ATLANTIC_WEBKIT_HLS_SUPPORT}"

    # ── GStreamer buffer tuning (via patched WebKit source) ──────────────────
    export WEBKIT_GST_BUFFER_SIZE="${WEBKIT_GST_BUFFER_SIZE:-10485760}"        # 10 MB ring buffer
    export WEBKIT_GST_QUEUE_HIGH_WATERMARK="${WEBKIT_GST_QUEUE_HIGH_WATERMARK:-0.05}"    # 5% fill threshold (was hardcoded 10%)
    export WEBKIT_GST_RING_BUFFER_MAX_SIZE="${WEBKIT_GST_RING_BUFFER_MAX_SIZE:-16777216}"  # 16 MB ring buffer (was 2 MB)
    export WEBKIT_GST_URIDECODEBIN_BUFFER_SIZE="${WEBKIT_GST_URIDECODEBIN_BUFFER_SIZE:-8388608}"  # 8 MB multiqueue (was 2 MB)
    export WPE_SHELL_MEDIA_DISK_CACHE_SIZE_BYTES="${WPE_SHELL_MEDIA_DISK_CACHE_SIZE_BYTES:-67108864}"  # 64 MB disk cache

    # ── GStreamer debug (uncomment to diagnose buffering issues) ──────────────
    # export GST_DEBUG="${GST_DEBUG:-webkit*:4,GstQueue2:3}"

    # ── JSC JIT thread tuning (Snapdragon 665: 8-core big.LITTLE) ────────────
    # Default JSC spawns 7 FTL threads + 8 GC markers on an 8-core device,
    # flooding the CPU during page load.  Cap to sane mobile limits.
    export JSC_numberOfFTLCompilerThreads=2
    export JSC_numberOfDFGCompilerThreads=2
    export JSC_numberOfBaselineCompilerThreads=2
    export JSC_numberOfGCMarkers=2
    export JSC_maxNumberOfWorklistThreads=4
    export JSC_worklistLoadFactor=20
    export JSC_worklistFTLLoadWeight=20
    export JSC_worklistDFGLoadWeight=5
    export JSC_worklistBaselineLoadWeight=2

    # ── JSC JIT tier-up thresholds ────────────────────────────────────────────
    # Lower thresholds so hot functions reach JIT earlier without waiting for
    # the default call-count watermarks (500/1000).
    export JSC_thresholdForJITAfterWarmUp=50
    export JSC_thresholdForOptimizeAfterWarmUp=200
    export JSC_forceDebuggerBytecodeGeneration=0

    # ── JSC GC heap tuning ────────────────────────────────────────────────────
    # Cap JS heap at 35% of available RAM. Setting 0.8/0.9 let the heap grow
    # to ~900 MB before GC, pushing this device into heavy zram swap (884/1024 MB
    # used) — swap latency is far worse than GC churn. 35% ≈ 350 MB for JS
    # on this 3.5 GB device, enough for large SPAs without thrashing swap.
    export JSC_smallHeapRAMFraction=0.50
    export JSC_largeHeapRAMFraction=0.50
    export JSC_largeHeapSize=67108864
    # Disable type-profiling heap snapshot (fires on every GC).  On the device
    # this saves ~3-8 MB of heap overhead and removes a frequent allocation
    # hot spot in the GC finaliser.
    export JSC_useTypeProfiler=0
    export JSC_useControlFlowProfiler=0

    # ── Skia painting thread caps (Adreno 610: single GPU command queue) ──────
    export WEBKIT_SKIA_GPU_PAINTING_THREADS=3
    export WEBKIT_SKIA_CPU_PAINTING_THREADS=2

    # ── Tile size alignment ───────────────────────────────────────────────────
    # 256 px tiles for Adreno 610 — smaller texture uploads reduce GPU pipeline
    # stalls vs 512 px, avoiding dropped frames during scroll on limited-bandwidth GPUs.
    export WEBKIT_LAYERS_TILE_SIZE=256
}

atlantic_cleanup_runtime_artifacts() {
    rm -rf "${ATLANTIC_XDG_RUNTIME_DIR}/.flatpak"/webkit-* \
           "${ATLANTIC_XDG_RUNTIME_DIR}/wpe"/bus-proxy-* 2>/dev/null || true
}
