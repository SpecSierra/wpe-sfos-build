#!/bin/bash
set -euo pipefail

DURATION_SECONDS="${DURATION_SECONDS:-20}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-1}"
OUTPUT_PATH="${OUTPUT_PATH:-$(pwd)/phone-runtime-$(date -u +%Y%m%dT%H%M%SZ).csv}"
PHONE_USER="${PHONE_USER:-defaultuser}"
PHONE_HOST="${PHONE_HOST:-localhost}"
PHONE_SSH_PORT="${PHONE_SSH_PORT:-2222}"
PHONE_PASSWORD="${PHONE_PASSWORD:-root}"
PROCESS_NAMES="${PROCESS_NAMES:-atlantic-browser.bin WPEWebProcess WPEGPUProcess WPENetworkProcess}"

echo "timestamp_ms,process_name,pid,state,threads,vmrss_kb,utime_ticks,stime_ticks,cmdline" > "${OUTPUT_PATH}"

sample_once() {
    local local_timestamp_ms
    local_timestamp_ms="$(date +%s%3N)"
    sshpass -p "${PHONE_PASSWORD}" \
        ssh -o StrictHostKeyChecking=no -p "${PHONE_SSH_PORT}" "${PHONE_USER}@${PHONE_HOST}" \
        "TIMESTAMP_MS='${local_timestamp_ms}' PROCESS_NAMES='${PROCESS_NAMES}' bash -s" <<'EOF'
set -euo pipefail
for process_name in ${PROCESS_NAMES}; do
    pids="$(pidof "${process_name}" 2>/dev/null || true)"
    for pid in ${pids}; do
        [ -r "/proc/${pid}/status" ] || continue
        state="$(awk '/^State:/ {print $2}' "/proc/${pid}/status" | head -n1)"
        threads="$(awk '/^Threads:/ {print $2}' "/proc/${pid}/status" | head -n1)"
        vmrss_kb="$(awk '/^VmRSS:/ {print $2}' "/proc/${pid}/status" | head -n1)"
        utime_ticks="$(awk '{print $14}' "/proc/${pid}/stat" 2>/dev/null || echo 0)"
        stime_ticks="$(awk '{print $15}' "/proc/${pid}/stat" 2>/dev/null || echo 0)"
        cmdline="$(tr '\0' ' ' < "/proc/${pid}/cmdline" | sed 's/"/'\''/g')"
        printf '%s,%s,%s,%s,%s,%s,%s,%s,"%s"\n' \
            "${TIMESTAMP_MS}" \
            "${process_name}" \
            "${pid}" \
            "${state:-?}" \
            "${threads:-0}" \
            "${vmrss_kb:-0}" \
            "${utime_ticks:-0}" \
            "${stime_ticks:-0}" \
            "${cmdline}"
    done
done
EOF
}

iteration=0
max_iterations=$(( (DURATION_SECONDS + INTERVAL_SECONDS - 1) / INTERVAL_SECONDS ))
while [ "${iteration}" -lt "${max_iterations}" ]; do
    sample_once >> "${OUTPUT_PATH}" || true
    iteration=$((iteration + 1))
    if [ "${iteration}" -lt "${max_iterations}" ]; then
        sleep "${INTERVAL_SECONDS}"
    fi
done

echo "Saved runtime samples to ${OUTPUT_PATH}"
echo ""
echo "Peak VmRSS by process:"
awk -F, 'NR > 1 { gsub(/"/, "", $2); if ($6 + 0 > peak[$2]) peak[$2] = $6 + 0 } END { for (name in peak) printf "  %s: %s kB\n", name, peak[name] }' "${OUTPUT_PATH}" | sort
