#!/usr/bin/env python3

import argparse
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Write a simple shell environment file with comments and key/value entries."
    )
    parser.add_argument("output", help="Path to the output environment file")
    parser.add_argument(
        "--comment",
        action="append",
        default=[],
        help="Comment line to prepend to the file (without the leading '#')",
    )
    parser.add_argument(
        "--entry",
        action="append",
        nargs=2,
        metavar=("KEY", "VALUE"),
        default=[],
        help="Required KEY VALUE pair to emit",
    )
    parser.add_argument(
        "--optional-entry",
        action="append",
        nargs=2,
        metavar=("KEY", "VALUE"),
        default=[],
        help="Optional KEY VALUE pair to emit only when VALUE is non-empty",
    )
    return parser.parse_args()


def append_entry(lines: list[str], key: str, value: str, optional: bool) -> None:
    if optional and value == "":
        return
    lines.append(f"{key}={value}")


def main() -> None:
    args = parse_args()
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    lines: list[str] = [f"# {comment}" for comment in args.comment]
    for key, value in args.entry:
        append_entry(lines, key, value, optional=False)
    for key, value in args.optional_entry:
        append_entry(lines, key, value, optional=True)

    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
