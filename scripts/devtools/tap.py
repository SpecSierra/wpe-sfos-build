#!/usr/bin/env python3
"""Single tap at pixel (X, Y) on the device touchscreen.

Usage: tap.py X Y [hold_seconds]   (default hold 0.08s)
Requires evtouch.py alongside; run on-device with `devel-su -p`.
"""
import sys
import time

from evtouch import Touch


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: tap.py X Y [hold_seconds]")
    px, py = int(sys.argv[1]), int(sys.argv[2])
    hold = float(sys.argv[3]) if len(sys.argv) > 3 else 0.08
    with Touch() as t:
        sys.stderr.write("abs x[%d,%d] y[%d,%d] -> (%d,%d)\n"
                         % (t.xmin, t.xmax, t.ymin, t.ymax, t.ax(px), t.ay(py)))
        t.down(px, py)
        time.sleep(hold)
        t.up()


if __name__ == "__main__":
    main()
