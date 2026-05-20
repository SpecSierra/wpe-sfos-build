#!/bin/bash
set -euo pipefail

DURATION_SECONDS="${DURATION_SECONDS:-10}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-1}"
OUTPUT_PATH="${OUTPUT_PATH:-$(pwd)/phone-gpu-$(date -u +%Y%m%dT%H%M%SZ).csv}"
PHONE_USER="${PHONE_USER:-defaultuser}"
PHONE_HOST="${PHONE_HOST:-localhost}"
PHONE_SSH_PORT="${PHONE_SSH_PORT:-2222}"
PHONE_PASSWORD="${PHONE_PASSWORD:-root}"

echo "timestamp_ms,busy_raw,total_raw,busy_percent,cur_freq_hz,sample_mode,interval_busy_raw,interval_total_raw" > "${OUTPUT_PATH}"

sample_once() {
    local local_timestamp_ms
    local_timestamp_ms="$(date +%s%3N)"
    sshpass -p "${PHONE_PASSWORD}" \
        ssh -o StrictHostKeyChecking=no -p "${PHONE_SSH_PORT}" "${PHONE_USER}@${PHONE_HOST}" \
        "TIMESTAMP_MS='${local_timestamp_ms}' bash -s" <<'EOF'
set -euo pipefail
busy_path="/sys/class/kgsl/kgsl-3d0/gpubusy"
freq_path="/sys/class/kgsl/kgsl-3d0/devfreq/cur_freq"
[ -r "${busy_path}" ] || exit 0
read -r busy_raw total_raw < "${busy_path}"
cur_freq_hz=0
[ -r "${freq_path}" ] && cur_freq_hz="$(cat "${freq_path}")"
printf '%s,%s,%s,,%s\n' "${TIMESTAMP_MS}" "${busy_raw}" "${total_raw}" "${cur_freq_hz}"
EOF
}

iteration=0
max_iterations=$(( (DURATION_SECONDS + INTERVAL_SECONDS - 1) / INTERVAL_SECONDS ))
while [ "${iteration}" -lt "${max_iterations}" ]; do
    if ! sample_once >> "${OUTPUT_PATH}"; then
        echo "warning: failed GPU sample ${iteration}" >&2
    fi
    iteration=$((iteration + 1))
    if [ "${iteration}" -lt "${max_iterations}" ]; then
        sleep "${INTERVAL_SECONDS}"
    fi
done

python3 - "${OUTPUT_PATH}" <<'PY'
import csv
import sys

path = sys.argv[1]
rows = []
with open(path, newline="", encoding="utf-8") as handle:
    reader = csv.DictReader(handle)
    for row in reader:
        rows.append(row)

def parse_int(row, key):
    value = (row.get(key) or "").strip()
    return int(value) if value else 0

counter_reset_detected = False
for previous, current in zip(rows, rows[1:]):
    if parse_int(current, "busy_raw") < parse_int(previous, "busy_raw"):
        counter_reset_detected = True
        break
    if parse_int(current, "total_raw") < parse_int(previous, "total_raw"):
        counter_reset_detected = True
        break

sample_mode = "window" if counter_reset_detected else "cumulative"

for index, row in enumerate(rows):
    row["sample_mode"] = "warmup" if index == 0 else sample_mode
    row["interval_busy_raw"] = ""
    row["interval_total_raw"] = ""

if sample_mode == "cumulative":
    for previous, current in zip(rows, rows[1:]):
        delta_busy = parse_int(current, "busy_raw") - parse_int(previous, "busy_raw")
        delta_total = parse_int(current, "total_raw") - parse_int(previous, "total_raw")
        current["interval_busy_raw"] = str(delta_busy)
        current["interval_total_raw"] = str(delta_total)
        busy_percent = (delta_busy / delta_total * 100.0) if delta_total > 0 else 0.0
        current["busy_percent"] = f"{busy_percent:.3f}"
else:
    initial_busy = parse_int(rows[0], "busy_raw") if rows else 0
    initial_total = parse_int(rows[0], "total_raw") if rows else 0
    first_usable_index = 1
    if initial_busy or initial_total:
        for index, current in enumerate(rows[1:], start=1):
            if parse_int(current, "busy_raw") != initial_busy or parse_int(current, "total_raw") != initial_total:
                first_usable_index = index
                break
        else:
            first_usable_index = len(rows)

        for skipped in rows[1:first_usable_index]:
            skipped["sample_mode"] = "warmup"

    for current in rows[first_usable_index:]:
        interval_busy = parse_int(current, "busy_raw")
        interval_total = parse_int(current, "total_raw")
        current["interval_busy_raw"] = str(interval_busy)
        current["interval_total_raw"] = str(interval_total)
        busy_percent = (interval_busy / interval_total * 100.0) if interval_total > 0 else 0.0
        current["busy_percent"] = f"{busy_percent:.3f}"

with open(path, "w", newline="", encoding="utf-8") as handle:
    fieldnames = [
        "timestamp_ms",
        "busy_raw",
        "total_raw",
        "busy_percent",
        "cur_freq_hz",
        "sample_mode",
        "interval_busy_raw",
        "interval_total_raw",
    ]
    writer = csv.DictWriter(handle, fieldnames=fieldnames)
    writer.writeheader()
    for row in rows:
        writer.writerow({key: row.get(key, "") for key in fieldnames})

busy_values = [float(row["busy_percent"]) for row in rows if row.get("busy_percent")]
freq_values = [int(row["cur_freq_hz"]) for row in rows if row.get("cur_freq_hz")]
print(f"Saved GPU samples to {path}")
print(f"Detected gpubusy mode: {sample_mode}")
if sample_mode == "window":
    print("Ignored the first sample as warmup because the counters appear to reset or report per-read windows.")
if busy_values:
    print(f"Average GPU busy: {sum(busy_values) / len(busy_values):.2f}%")
    print(f"Peak GPU busy: {max(busy_values):.2f}%")
if freq_values:
    print(f"Peak GPU frequency: {max(freq_values)} Hz")
PY
