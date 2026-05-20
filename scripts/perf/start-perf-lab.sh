#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${PORT:-8000}"
BIND="${BIND:-0.0.0.0}"
RESULTS_DIR="${RESULTS_DIR:-${SCRIPT_DIR}/results}"

mkdir -p "${RESULTS_DIR}"

HOST_IPS="$(hostname -I 2>/dev/null | xargs echo || true)"

echo "Starting Atlantic perf lab"
echo "  bind:        ${BIND}"
echo "  port:        ${PORT}"
echo "  results dir: ${RESULTS_DIR}"
if [ -n "${HOST_IPS}" ]; then
    echo "  host IPs:    ${HOST_IPS}"
fi
echo ""
echo "Useful URLs after the phone tunnel is open:"
echo "  http://127.0.0.1:${PORT}/probe.html?mode=probe&run=probe-baseline"
echo "  http://127.0.0.1:${PORT}/probe.html?mode=dom&run=dom-baseline"
echo "  http://127.0.0.1:${PORT}/probe.html?mode=canvas2d&run=canvas2d-baseline"
echo "  http://127.0.0.1:${PORT}/probe.html?mode=webgl&run=webgl-baseline"
echo ""
echo "Open the reverse tunnel with:"
echo "  ${SCRIPT_DIR}/open-phone-tunnel.sh"
echo ""

exec python3 "${SCRIPT_DIR}/perf_lab.py" \
    --bind "${BIND}" \
    --port "${PORT}" \
    --results-dir "${RESULTS_DIR}"
