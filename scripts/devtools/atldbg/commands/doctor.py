"""doctor — one-shot health snapshot across every subsystem.

A fast triage that answers "what state is the browser in right now?": processes
alive, inspector reachable, current URL + document state, JS errors waiting in the
console, any media elements and their decode health, a quick CPU snapshot, and
device memory pressure.  Run this first; drill in with the focused commands.
"""
from __future__ import annotations

import asyncio
import json

from .. import cdp, device, ui
from . import cpu as cpu_cmd


def _meminfo():
    out = device.ssh("cat /proc/meminfo; echo ---; free -m 2>/dev/null").stdout
    total = avail = None
    for line in out.splitlines():
        if line.startswith("MemTotal:"):
            total = int(line.split()[1]) // 1024
        elif line.startswith("MemAvailable:"):
            avail = int(line.split()[1]) // 1024
    return total, avail


async def _run(args):
    ui.heading("doctor — Atlantic browser health")

    if not device.reachable():
        ui.err("device not reachable over ssh (port 2222). Is the tunnel up?")
        return 1
    ui.ok("device reachable")

    procs = device.processes()
    if not procs["ui"]:
        ui.err("browser NOT running. Start it: atldbg launch <url>")
        return 1
    ui.ok(f"UIProcess pid {procs['ui']}, "
          f"{len(procs['web'])} WebProcess, {len(procs['network'])} NetworkProcess")

    total, avail = _meminfo()
    if total:
        used_frac = 1 - (avail / total if avail else 0)
        ui.kv("memory", f"{avail}/{total} MB free  {ui.bar(used_frac, 18)}")

    # quick 2s CPU snapshot
    sample_pids = [procs["ui"]] + procs["web"] + procs["network"]
    a = cpu_cmd._read_stats(sample_pids)
    await asyncio.sleep(2)
    b = cpu_cmd._read_stats(sample_pids)
    per = {}
    for tid, (comm, j1, owner) in b.items():
        if tid in a:
            dj = j1 - a[tid][1]
            if dj > 0:
                per[owner] = per.get(owner, 0.0) + dj / (2 * cpu_cmd.CLK_TCK) * 100
    if per:
        names = {procs["ui"]: "UI"}
        for p in procs["web"]:
            names[p] = "Web"
        cpu_str = "  ".join(f"{names.get(o,'?')}:{v:.0f}%"
                            for o, v in sorted(per.items(), key=lambda x: -x[1]))
        ui.kv("cpu (2s)", cpu_str)

    # inspector-side state
    try:
        async with cdp.connect_session(discover_timeout=4) as s:
            ui.ok("remote inspector reachable")
            url = await s.eval_value("location.href", default="?")
            rs = await s.eval_value("document.readyState", default="?")
            ui.kv("page", f"{url}  ({rs})")

            # collect a short burst of live console errors, excluding the engine's
            # own [WPE-...] diagnostics (logged at error level but not page bugs).
            errors = []

            def _on_err(p):
                m = p.get("message", {})
                if m.get("level") != "error":
                    return
                if (m.get("text") or "").lstrip().startswith("[WPE-"):
                    return
                errors.append(m)
            s.on("Console.messageAdded", _on_err)
            await s.enable("Console")
            await s.pump(2.0)
            if errors:
                ui.warn(f"{len(errors)} JS error(s) in last 2s:")
                for m in errors[:4]:
                    print(ui.c(f"      {m.get('text','')[:120]}", "grey"))
            else:
                ui.ok("no JS errors in the last 2s")

            media = json.loads(await s.eval_value(
                "JSON.stringify([].map.call(document.querySelectorAll('video,audio'),"
                "function(m){var o={tag:m.tagName,paused:m.paused};"
                "if(m.tagName==='VIDEO'){try{var q=m.getVideoPlaybackQuality();"
                "o.dropped=q.droppedVideoFrames;o.total=q.totalVideoFrames;}catch(e){}}return o;}))",
                default="[]"))
            if media:
                for m in media:
                    extra = (f" dropped={m.get('dropped')}/{m.get('total')}"
                             if m.get("tag") == "VIDEO" else "")
                    ds = "yellow" if m.get("dropped") else "grey"
                    ui.kv(f"{m['tag'].lower()}",
                          ui.c(("playing" if not m["paused"] else "paused") + extra, ds))
            else:
                ui.info("no media elements")
    except Exception as e:
        ui.warn(f"inspector not reachable: {e}")

    print()
    ui.info("drill in: atldbg bug | cpu | profile | media | render")
    return 0


def run(args):
    return asyncio.run(_run(args))
