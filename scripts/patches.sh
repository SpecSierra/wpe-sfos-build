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
    "patches/webkit/webkit-renderbox-isnan.patch"
    "patches/webkit/webkit-shapeoutside-isnan.patch"
    "patches/webkit/webkit-gpu-process-by-default-wpe.patch"
    "patches/webkit/webkit-gpu-process-egl-default-display-fallback.patch"
    "patches/webkit/webkit-jsc-linux-arm64-thread-tuning.patch"
)

readonly QT5_PLUGIN_PATCHES=(
    "patches/qt-bridge/qt5-plugin-texture-cache.patch"
    "patches/qt-bridge/qt5-plugin-exported-image-lifetime.patch"
    "patches/qt-bridge/qt5-plugin-displayimage-window-update.patch"
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
