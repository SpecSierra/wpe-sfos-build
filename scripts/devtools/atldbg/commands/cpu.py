"""cpu — find what is *executing*: per-thread CPU sampling of the browser.

The Atlantic engine spreads work across many named threads (WebKit main, the
Core:Scrolling compositor thread, JSC GC markers, Skia raster workers, GStreamer
decode threads...).  This samples /proc/<pid>/task/<tid>/stat twice over an
interval and attributes CPU% per thread, grouped by process, so you can see
exactly which thread is burning the core during a scroll / video / load.

Native, build-independent, no inspector needed.
"""
from __future__ import annotations

import time

from .. import device, ui

CLK_TCK = 100  # USER_HZ on this aarch64 kernel (getconf CLK_TCK == 100)


def _read_stats(pids):
    """Return {tid: (comm, jiffies, pid)} for every thread of every pid.

    One ssh round-trip: dumps every task stat line prefixed with its owner pid.
    """
    script = "; ".join(
        f'for t in /proc/{p}/task/*/stat; do echo -n "{p}|"; cat "$t" 2>/dev/null; done'
        for p in pids
    )
    out = device.ssh(script).stdout
    res = {}
    for line in out.splitlines():
        if "|" not in line:
            continue
        owner, _, stat = line.partition("|")
        # comm is parenthesised and may contain spaces/parens -> split on last ')'
        head, _, tail = stat.rpartition(")")
        if not head:
            continue
        try:
            tid = int(head.split(None, 1)[0])
            comm = head.split("(", 1)[1]
            fields = tail.split()
            utime, stime = int(fields[11]), int(fields[12])
        except (ValueError, IndexError):
            continue
        res[tid] = (comm, utime + stime, int(owner))
    return res


def run(args):
    procs = device.processes()
    pids = []
    label = {}
    if procs["ui"]:
        pids.append(procs["ui"]); label[procs["ui"]] = "UIProcess"
    for p in procs["web"]:
        pids.append(p); label[p] = "WebProcess"
    for p in procs["network"]:
        pids.append(p); label[p] = "NetworkProcess"
    for p in procs["gpu"]:
        pids.append(p); label[p] = "GPUProcess"
    if not pids:
        ui.err("browser not running (no UI/Web process found). Try: atldbg launch <url>")
        return 1

    interval = args.seconds
    ui.heading(f"CPU — per-thread sampling over {interval:.0f}s")
    ui.info("scroll / play video now to capture the hot path…")

    a = _read_stats(pids)
    t0 = time.monotonic()
    time.sleep(interval)
    b = _read_stats(pids)
    dt = time.monotonic() - t0

    rows = []
    per_proc = {}
    for tid, (comm, j1, owner) in b.items():
        if tid not in a:
            continue
        dj = j1 - a[tid][1]
        if dj <= 0:
            continue
        pct = dj / (dt * CLK_TCK) * 100.0
        rows.append((pct, owner, tid, comm))
        per_proc[owner] = per_proc.get(owner, 0.0) + pct

    rows.sort(reverse=True)

    print()
    for owner in sorted(per_proc, key=lambda o: -per_proc[o]):
        name = label.get(owner, "?")
        tot = per_proc[owner]
        print(f"{ui.c(name, 'bold', 'cyan')} (pid {owner})  "
              f"{ui.c(f'{tot:5.1f}% CPU', 'bold')}  {ui.bar(tot / 100.0)}")
    print()

    shown = [r for r in rows if r[0] >= args.threshold][: args.top]
    if not shown:
        ui.info("no thread above threshold — engine was idle during the window.")
        return 0
    print(f"  {'CPU%':>6}  {'thread (comm)':<22} {'process':<14} tid")
    print("  " + ui.c("─" * 56, "grey"))
    for pct, owner, tid, comm in shown:
        style = "red" if pct >= 40 else "yellow" if pct >= 15 else "green"
        print(f"  {ui.c(f'{pct:6.1f}', style)}  {comm[:22]:<22} "
              f"{label.get(owner,'?'):<14} {tid}")
    return 0
