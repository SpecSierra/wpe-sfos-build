#!/bin/sh

ATLANTIC_RUNTIME_PREFIX="${ATLANTIC_RUNTIME_PREFIX:-/opt/wpe-sfos}"
ATLANTIC_RUNTIME_LIBDIR="${ATLANTIC_RUNTIME_LIBDIR:-/usr/lib64}"
ATLANTIC_COMPAT_DIR="${ATLANTIC_COMPAT_DIR:-${ATLANTIC_RUNTIME_LIBDIR}/wpe-compat}"
ATLANTIC_WPE_HELPER_DIR="${ATLANTIC_WPE_HELPER_DIR:-/usr/libexec/wpe-webkit-2.0}"
ATLANTIC_QT_QPA_PLATFORM="${ATLANTIC_QT_QPA_PLATFORM:-wayland}"
ATLANTIC_XDG_RUNTIME_DIR="${ATLANTIC_XDG_RUNTIME_DIR:-/run/user/100000}"
ATLANTIC_WAYLAND_DISPLAY="${ATLANTIC_WAYLAND_DISPLAY:-../../display/wayland-0}"
ATLANTIC_GSTREAMER_PLUGIN_DIR="${ATLANTIC_GSTREAMER_PLUGIN_DIR:-${ATLANTIC_RUNTIME_LIBDIR}/gstreamer-1.0}"
ATLANTIC_GST_PLUGIN_FEATURE_RANK="${ATLANTIC_GST_PLUGIN_FEATURE_RANK:-droidvdec:0,droidvenc:0}"
ATLANTIC_WEBKIT_HLS_SUPPORT="${ATLANTIC_WEBKIT_HLS_SUPPORT:-1}"
ATLANTIC_BROWSER_RUNTIME_DELAY_MS="${ATLANTIC_BROWSER_RUNTIME_DELAY_MS:-2000}"

atlantic_default_pulse_server() {
    if [ -S "${ATLANTIC_XDG_RUNTIME_DIR}/pulse/native" ]; then
        printf 'unix:%s/pulse/native' "${ATLANTIC_XDG_RUNTIME_DIR}"
    fi
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
    export ATLANTIC_BROWSER_RUNTIME_DELAY_MS="${ATLANTIC_BROWSER_RUNTIME_DELAY_MS}"
    export WEBKIT_GST_ENABLE_HLS_SUPPORT="${ATLANTIC_WEBKIT_HLS_SUPPORT}"
}

atlantic_cleanup_runtime_artifacts() {
    rm -rf "${ATLANTIC_XDG_RUNTIME_DIR}/.flatpak"/webkit-* \
           "${ATLANTIC_XDG_RUNTIME_DIR}/wpe"/bus-proxy-* 2>/dev/null || true
}
