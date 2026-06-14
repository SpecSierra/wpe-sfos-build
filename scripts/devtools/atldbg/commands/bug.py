"""bug — find bugs: live console errors, JS exceptions, and failed network loads.

Streams the page's Console messages (uncaught JS exceptions surface here too, with
their call stack), Network load failures, and — to catch the nastiest class of
Atlantic bug — WebProcess crashes detected by watching the process table while
listening.  Filterable to errors-only.
"""
from __future__ import annotations

import asyncio
import time

from .. import cdp, device, ui

_LEVEL_STYLE = {"error": "bred", "warning": "byellow", "log": "grey",
                "info": "blue", "debug": "grey"}


def _fmt_console(msg: dict) -> str | None:
    level = msg.get("level", "log")
    text = (msg.get("text") or "").replace("\n", " ")[:400]
    src = msg.get("url", "")
    loc = ""
    if src:
        loc = ui.c(f"  ({src.split('/')[-1][:50]}:{msg.get('line')})", "grey")
    tag = ui.c(f"[{level}]", _LEVEL_STYLE.get(level, "grey"))
    line = f"{tag} {text}{loc}"
    # uncaught exceptions carry a stackTrace — show the top frames, indented
    st = msg.get("stackTrace")
    frames = (st or {}).get("callFrames") if isinstance(st, dict) else st
    if level == "error" and frames:
        for f in frames[:4]:
            fn = f.get("functionName") or "(anonymous)"
            u = (f.get("url") or "").split("/")[-1]
            line += ui.c(f"\n      at {fn} ({u}:{f.get('lineNumber', f.get('line'))})", "grey")
    return line


async def _run(args):
    errors_only = args.errors
    seen_console = 0
    seen_neterr = 0

    async with cdp.connect_session(match=getattr(args, "tab", None)) as s:
        url = await s.eval_value("location.href", default="?")
        ui.heading(f"bug — watching {url}")
        ui.info(f"streaming console + network failures for {args.seconds:.0f}s "
                f"({'errors only' if errors_only else 'all levels'}); reproduce the bug now…")
        print()

        def on_console(p):
            nonlocal seen_console
            msg = p.get("message", {})
            if errors_only and msg.get("level") not in ("error",):
                return
            out = _fmt_console(msg)
            if out:
                seen_console += 1
                print(out)

        def on_netfail(p):
            nonlocal seen_neterr
            if p.get("canceled"):
                return
            seen_neterr += 1
            print(ui.c("[net] ", "magenta")
                  + ui.c(p.get("errorText", "load failed")[:200], "yellow")
                  + ui.c(f"  req={p.get('requestId')}", "grey"))

        s.on("Console.messageAdded", on_console)
        s.on("Network.loadingFailed", on_netfail)
        await s.enable("Console", "Network", "Runtime")

        # Watch for WebProcess death concurrently (the classic tab crash).
        web_before = set(device.processes()["web"])

        await s.pump(args.seconds)

        web_after = set(device.processes()["web"])
        gone = web_before - web_after

    print()
    ui.info(f"{seen_console} console message(s), {seen_neterr} network failure(s)")
    if gone:
        ui.err(f"WebProcess CRASHED during capture: pid(s) {sorted(gone)} disappeared")
        ui.info("recent /tmp/atl.log tail:")
        print(ui.c(device.log_tail(15), "grey"))
    return 0


def run(args):
    return asyncio.run(_run(args))
