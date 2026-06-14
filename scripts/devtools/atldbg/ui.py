"""Tiny terminal formatting helpers (colour, headings, tables, bars).

No third-party deps.  Colour auto-disables when stdout is not a TTY so piped
output stays clean.
"""
from __future__ import annotations

import os
import shutil
import sys

_TTY = sys.stdout.isatty() and os.environ.get("NO_COLOR") is None

_C = {
    "reset": "\033[0m", "bold": "\033[1m", "dim": "\033[2m",
    "red": "\033[31m", "green": "\033[32m", "yellow": "\033[33m",
    "blue": "\033[34m", "magenta": "\033[35m", "cyan": "\033[36m",
    "grey": "\033[90m", "bred": "\033[91m", "bgreen": "\033[92m",
    "byellow": "\033[93m", "bcyan": "\033[96m",
}


def c(text, *styles) -> str:
    if not _TTY:
        return str(text)
    pre = "".join(_C.get(s, "") for s in styles)
    return f"{pre}{text}{_C['reset']}" if pre else str(text)


def heading(text: str) -> None:
    width = min(shutil.get_terminal_size((80, 24)).columns, 80)
    line = "─" * width
    print(c(line, "grey"))
    print(c(f" {text}", "bold", "cyan"))
    print(c(line, "grey"))


def kv(key: str, value, width: int = 22) -> None:
    print(f"  {c(key.ljust(width), 'grey')} {value}")


def bar(frac: float, width: int = 24) -> str:
    frac = max(0.0, min(1.0, frac))
    filled = int(round(frac * width))
    style = "green" if frac < 0.5 else "yellow" if frac < 0.8 else "red"
    return c("█" * filled, style) + c("░" * (width - filled), "grey")


def warn(text: str) -> None:
    print(c("! ", "byellow") + text)


def err(text: str) -> None:
    print(c("✗ ", "bred") + text)


def ok(text: str) -> None:
    print(c("✓ ", "bgreen") + text)


def info(text: str) -> None:
    print(c("· ", "grey") + text)
