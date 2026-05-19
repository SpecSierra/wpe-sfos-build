#!/bin/bash

readonly ENGINE_SOURCE_PATCHES=(
    "libepoxy-rtld-default-fallback.patch"
)

readonly WEBKIT_SOURCE_PATCHES=(
    "webkit-quirks-no-video.patch"
)

readonly QT5_PLUGIN_PATCHES=(
    "qt5-plugin-gnuinstalldirs.patch"
    "wpeqtview-sfos-api.patch"
    "wpeqtview-viewport-scale.patch"
    "qt5-plugin-epoxy-gl-fix.patch"
)

apply_repo_patches() {
    local strip_level="$1"
    local target_dir="$2"
    shift 2

    local patch_file
    for patch_file in "$@"; do
        if [ ! -f "${BUILD_TOOLS}/${patch_file}" ]; then
            echo "ERROR: missing patch ${BUILD_TOOLS}/${patch_file}" >&2
            return 1
        fi

        echo "  Applying ${patch_file}"
        (
            cd "${target_dir}"
            patch "-p${strip_level}" --forward < "${BUILD_TOOLS}/${patch_file}" || true
        )
    done
}
