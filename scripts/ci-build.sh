#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

export WORK="${WORK:-$(cd "${REPO_ROOT}/.." && pwd)}"
export BUILD_TOOLS="${BUILD_TOOLS:-${REPO_ROOT}}"
export BROWSER_SRC="${BROWSER_SRC:-${WORK}/sailfish-browser-wpe}"
export WPE_PREFIX="${WPE_PREFIX:-${WORK}/wpe-sfos-prefix}"
export SYSROOT="${SYSROOT:-/opt/github-runner/cache/sfos-sysroot-5.0.0.62}"
export OUT="${OUT:-/tmp/wpe-sfos-rpms}"
export STAGING="${STAGING:-/tmp/wpe-sfos-stage}"

ARTIFACT_ROOT="${ARTIFACT_ROOT:-${REPO_ROOT}/artifacts}"
LOG_PATH="${LOG_PATH:-${ARTIFACT_ROOT}/build.log}"
SUMMARY_PATH="${SUMMARY_PATH:-${ARTIFACT_ROOT}/summary.txt}"

rm -rf "${ARTIFACT_ROOT}/rpms" "${ARTIFACT_ROOT}/build-config"
mkdir -p "${ARTIFACT_ROOT}" "${OUT}" "${STAGING}"

cat > "${SUMMARY_PATH}" <<EOF
repo_root=${REPO_ROOT}
work=${WORK}
build_tools=${BUILD_TOOLS}
browser_src=${BROWSER_SRC}
wpe_prefix=${WPE_PREFIX}
sysroot=${SYSROOT}
out=${OUT}
staging=${STAGING}
started_at=$(date --iso-8601=seconds)
EOF

bash "${REPO_ROOT}/build-all.sh" 2>&1 | tee "${LOG_PATH}"

mkdir -p "${ARTIFACT_ROOT}/rpms"
shopt -s nullglob
rpms=("${OUT}"/*.rpm)
if [ "${#rpms[@]}" -eq 0 ]; then
    echo "ERROR: build completed without producing RPMs in ${OUT}" >&2
    exit 1
fi

cp -a "${rpms[@]}" "${ARTIFACT_ROOT}/rpms/"

if [ -d "${WPE_PREFIX}/share/wpe-webkit-2.0/build-config" ]; then
    cp -a "${WPE_PREFIX}/share/wpe-webkit-2.0/build-config" "${ARTIFACT_ROOT}/build-config"
fi

{
    echo "completed_at=$(date --iso-8601=seconds)"
    echo "rpm_count=${#rpms[@]}"
} >> "${SUMMARY_PATH}"
