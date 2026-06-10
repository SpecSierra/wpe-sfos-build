#!/usr/bin/env python3
"""Drag/flick from (X1, Y1) to (X2, Y2) over ~20 steps.

Usage: swipe.py X1 Y1 X2 Y2
Requires evtouch.py alongside; run on-device with `devel-su -p`.
"""
import sys
import time

from evtouch import Touch

STEPS = 20


def main():
    if len(sys.argv) < 5:
        sys.exit("usage: swipe.py X1 Y1 X2 Y2")
    x1, y1, x2, y2 = map(int, sys.argv[1:5])
    with Touch() as t:
        t.down(x1, y1)
        for i in range(1, STEPS + 1):
            cx = x1 + (x2 - x1) * i // STEPS
            cy = y1 + (y2 - y1) * i // STEPS
            t.move(cx, cy)
            time.sleep(0.012)
        t.up()


if __name__ == "__main__":
    main()
