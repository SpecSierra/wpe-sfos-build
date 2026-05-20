#!/usr/bin/env python3

import argparse
import re
from pathlib import Path


INTERESTING_FLAGS = (
    "ENABLE_GPU_PROCESS",
    "ENABLE_WEBGL",
    "ENABLE_WEBGPU",
    "USE_GBM",
    "ENABLE_BUBBLEWRAP_SANDBOX",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Write a small summary of the interesting WebKit build flags."
    )
    parser.add_argument("cache_path", help="Path to CMakeCache.txt")
    parser.add_argument("output_path", help="Path to the feature-flags output file")
    parser.add_argument("webkit_version", help="WebKit version to record in the summary")
    parser.add_argument(
        "--source-dir",
        help="Optional source directory to record in the summary",
    )
    parser.add_argument(
        "--build-dir",
        help="Optional build directory to record in the summary",
    )
    return parser.parse_args()


def read_flags(cache_path: Path) -> dict[str, str]:
    values = {key: "<not found>" for key in INTERESTING_FLAGS}
    pattern = re.compile(r"^([^:#=]+):[^=]+=(.*)$")

    if not cache_path.is_file():
        return values

    for line in cache_path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = pattern.match(line)
        if not match:
            continue
        key, value = match.groups()
        if key in values:
            values[key] = value

    return values


def main() -> None:
    args = parse_args()
    cache_path = Path(args.cache_path)
    output_path = Path(args.output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    build_dir = args.build_dir or str(cache_path.parent)
    values = read_flags(cache_path)

    lines = [
        f"WPE WebKit version: {args.webkit_version}",
    ]
    if args.source_dir:
        lines.append(f"Source dir: {args.source_dir}")
    lines.append(f"Build dir: {build_dir}")
    lines.append("")
    lines.extend(f"{key}={values[key]}" for key in INTERESTING_FLAGS)

    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
