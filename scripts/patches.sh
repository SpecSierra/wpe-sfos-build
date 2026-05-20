#!/bin/bash

readonly ENGINE_SOURCE_PATCHES=(
    "libepoxy-rtld-default-fallback.patch"
)

readonly WEBKIT_SOURCE_PATCHES=(
    "webkit-quirks-no-video.patch"
    "webkit-icu-imported-targets.patch"
    "webkit-ramsize-cstddef.patch"
    "webkit-wtf-header-includes.patch"
    "webkit-renderbox-isnan.patch"
    "webkit-shapeoutside-isnan.patch"
)

readonly QT5_PLUGIN_PATCHES=(
    "qt5-plugin-texture-cache.patch"
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
