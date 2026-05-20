#!/usr/bin/env python3
import argparse
import hashlib
import json
import math
import time
import urllib.request
from datetime import datetime, timezone


def percentile(sorted_values, fraction):
    if not sorted_values:
        return None
    if len(sorted_values) == 1:
        return sorted_values[0]
    index = (len(sorted_values) - 1) * fraction
    lower = math.floor(index)
    upper = math.ceil(index)
    if lower == upper:
        return sorted_values[lower]
    return sorted_values[lower] + (sorted_values[upper] - sorted_values[lower]) * (index - lower)


def parse_args():
    parser = argparse.ArgumentParser(description="Estimate Screencast MJPEG frame cadence and unique-frame rate.")
    parser.add_argument("url", help="MJPEG stream URL, for example http://localhost:5554")
    parser.add_argument("--duration", type=float, default=5.0, help="Sampling duration in seconds. Default: 5")
    parser.add_argument("--output", help="Optional JSON output path")
    return parser.parse_args()


def main():
    args = parse_args()
    start_monotonic = time.monotonic()
    end_monotonic = start_monotonic + args.duration

    frames = []
    intervals_ms = []
    changed_frames = 0
    last_frame_hash = None
    last_timestamp = None
    buffer = b""

    with urllib.request.urlopen(args.url, timeout=max(10, int(args.duration) + 5)) as response:
        while time.monotonic() < end_monotonic:
            chunk = response.read(16384)
            if not chunk:
                break
            buffer += chunk

            while True:
                start = buffer.find(b"\xff\xd8")
                if start < 0:
                    if len(buffer) > 131072:
                        buffer = buffer[-65536:]
                    break
                end = buffer.find(b"\xff\xd9", start + 2)
                if end < 0:
                    if start > 0:
                        buffer = buffer[start:]
                    break

                frame = buffer[start:end + 2]
                buffer = buffer[end + 2:]
                timestamp = time.monotonic()
                frame_hash = hashlib.sha1(frame).hexdigest()
                if frame_hash != last_frame_hash:
                    changed_frames += 1
                    last_frame_hash = frame_hash
                if last_timestamp is not None:
                    intervals_ms.append((timestamp - last_timestamp) * 1000.0)
                frames.append({"timestamp": timestamp, "hash": frame_hash, "bytes": len(frame)})
                last_timestamp = timestamp

                if timestamp >= end_monotonic:
                    break

    elapsed_seconds = (frames[-1]["timestamp"] - frames[0]["timestamp"]) if len(frames) >= 2 else 0.0
    frame_count = len(frames)
    sorted_intervals = sorted(intervals_ms)
    result = {
        "capturedAt": datetime.now(timezone.utc).isoformat(),
        "url": args.url,
        "durationRequestedSeconds": args.duration,
        "frameCount": frame_count,
        "changedFrameCount": changed_frames,
        "elapsedSeconds": elapsed_seconds,
        "deliveredFps": (frame_count / elapsed_seconds) if elapsed_seconds > 0 else 0.0,
        "changedFps": (changed_frames / elapsed_seconds) if elapsed_seconds > 0 else 0.0,
        "avgIntervalMs": (sum(intervals_ms) / len(intervals_ms)) if intervals_ms else None,
        "p50IntervalMs": percentile(sorted_intervals, 0.50),
        "p95IntervalMs": percentile(sorted_intervals, 0.95),
        "maxIntervalMs": max(intervals_ms) if intervals_ms else None,
    }

    encoded = json.dumps(result, indent=2, sort_keys=True)
    print(encoded)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(encoded + "\n")


if __name__ == "__main__":
    main()
