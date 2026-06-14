"""render — debug rendering / frame pacing / paint.

Measures frame cadence with an injected requestAnimationFrame meter (using
in-page performance.now(), which — unlike this build's inspector Timeline records,
whose timestamps come back as 0 — gives real per-frame deltas).  Reports fps,
p50/p95 frame time, jank (frames over the 33 ms budget) and the worst frame.

--scroll drives a programmatic auto-scroll during the window so the raster/paint
path is actually exercised (the scenario behind the tile-corruption / scroll-jank
work).  It also samples the compositor/raster thread CPU and grabs a screenshot at
the end so you can eyeball corruption.
"""
from __future__ import annotations

import asyncio
import json

from .. import cdp, device, ui
from . import cpu as cpu_cmd

_FPS = r"""
(function(){
  var st = window.__atldbg_fps || (window.__atldbg_fps = {deltas:[], gen:0});
  st.deltas = []; st.last = performance.now();
  var gen = ++st.gen;                 // invalidate any previous running loop
  function tick(now){
    if (gen !== st.gen) return;       // a newer run superseded us
    st.deltas.push(now - st.last); st.last = now; requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
  st.stop = function(){ st.gen++; return st.deltas; };
  return 'started';
})()
"""

_SCROLL = r"""
(function(){
  var dir=1, y=0, h=document.documentElement.scrollHeight-innerHeight;
  (function step(){
    y+=dir*24; if(y>=h){y=h;dir=-1;} if(y<=0){y=0;dir=1;}
    window.scrollTo(0,y);
    if(window.__atldbg_fps && window.__atldbg_fps.stop) requestAnimationFrame(step);
  })();
  return h;
})()
"""


def _pct(sorted_vals, p):
    if not sorted_vals:
        return 0.0
    i = min(len(sorted_vals) - 1, int(p / 100.0 * len(sorted_vals)))
    return sorted_vals[i]


async def _run(args):
    async with cdp.connect_session(match=getattr(args, "tab", None)) as s:
        url = await s.eval_value("location.href", default="?")
        ui.heading(f"render — {url}")
        if await s.eval_value("document.hidden", default=False):
            ui.warn("this tab is HIDDEN (screen off, or it's a background tab) — "
                    "rAF is suspended, so no frames will be measured.")
            ui.info("wake the device and bring this page to the foreground, then re-run.")
        state = await s.eval_value(f"({_FPS})", default="?")
        if args.scroll:
            await s.eval_value(f"({_SCROLL})")
            ui.info(f"auto-scrolling + measuring frames for {args.seconds:.0f}s…")
        else:
            ui.info(f"measuring frames for {args.seconds:.0f}s — scroll/animate now…")

        # sample compositor/raster CPU in parallel with the frame window
        procs = device.processes()
        sample_pids = ([procs["ui"]] if procs["ui"] else []) + procs["web"]
        a = cpu_cmd._read_stats(sample_pids) if sample_pids else {}
        await asyncio.sleep(args.seconds)
        b = cpu_cmd._read_stats(sample_pids) if sample_pids else {}

        deltas = await s.eval_value("JSON.stringify(window.__atldbg_fps.stop())",
                                    default="[]")

    deltas = [d for d in (json.loads(deltas) if isinstance(deltas, str) else deltas)
              if d and d > 0]
    print()
    if not deltas or len(deltas) < 2:
        ui.warn("no animation frames captured — the page wasn't rendering "
                "(compositor-thread scroll doesn't tick rAF; try --scroll).")
    else:
        deltas.sort()
        n = len(deltas)
        avg = sum(deltas) / n
        fps = 1000.0 / avg if avg else 0
        p50, p95, worst = _pct(deltas, 50), _pct(deltas, 95), deltas[-1]
        jank = sum(1 for d in deltas if d > 33.3)
        fstyle = "green" if fps >= 50 else "yellow" if fps >= 30 else "red"
        ui.kv("frames", f"{n} over {args.seconds:.0f}s")
        ui.kv("avg fps", ui.c(f"{fps:5.1f}", fstyle) + f"  ({avg:.1f} ms/frame)")
        ui.kv("frame time", f"p50={p50:.1f}ms  p95={p95:.1f}ms  worst={worst:.1f}ms")
        ui.kv("jank (>33ms)", (ui.c(str(jank), "red") if jank else ui.c("0", "green"))
              + f"  ({100.0*jank/n:.0f}% of frames)")

    # compositor / raster thread hotspots during the window
    rows = []
    for tid, (comm, j1, owner) in b.items():
        if tid in a:
            dj = j1 - a[tid][1]
            if dj > 0:
                rows.append((dj / (args.seconds * cpu_cmd.CLK_TCK) * 100.0, comm))
    rows.sort(reverse=True)
    hot = [r for r in rows if any(k in r[1].lower() for k in
           ("compos", "scroll", "raster", "skia", "paint", "gl", "render"))][:6]
    if hot:
        print()
        ui.info("render-path threads this window:")
        for pct, comm in hot:
            print(f"    {ui.c(f'{pct:5.1f}%', 'yellow')}  {comm}")

    if not args.no_shot:
        try:
            path = device.screenshot(args.shot)
            ui.ok(f"screenshot → {path}  (open it to check for tile corruption)")
        except Exception as e:
            ui.warn(f"screenshot failed: {e}")
    return 0


def run(args):
    return asyncio.run(_run(args))
