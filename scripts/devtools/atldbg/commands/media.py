"""media — debug video / audio playback.

Snapshots every <video>/<audio> element (source, ready/network state, buffered,
errors, and for video the decode quality: total / dropped / corrupted frames).
With --watch it samples twice and reports the decoded-frames-per-second and the
growth in dropped frames — the signal for the droidvdec / vp9 decode issues.

It also looks at the engine side: which GStreamer decode threads are live in the
WebProcess (e.g. droidvdec0:src for HW H.264/H.265, vp9dec for software VP9), the
configured GST_PLUGIN_FEATURE_RANK, and recent decoder log lines.
"""
from __future__ import annotations

import asyncio
import json

from .. import cdp, device, ui

_READY = ["HAVE_NOTHING", "HAVE_METADATA", "HAVE_CURRENT_DATA",
          "HAVE_FUTURE_DATA", "HAVE_ENOUGH_DATA"]
_NET = ["EMPTY", "IDLE", "LOADING", "NO_SOURCE"]

_SNAP = r"""
JSON.stringify([].map.call(document.querySelectorAll('video,audio'), function(m){
  function ranges(tr){ var r=[]; for(var i=0;i<tr.length;i++) r.push([+tr.start(i).toFixed(1),+tr.end(i).toFixed(1)]); return r; }
  var o = {
    tag:m.tagName, src:(m.currentSrc||m.src||'').slice(0,120),
    ready:m.readyState, net:m.networkState, paused:m.paused, ended:m.ended,
    t:+m.currentTime.toFixed(2), dur:(isFinite(m.duration)?+m.duration.toFixed(2):null),
    rate:m.playbackRate, vol:+m.volume.toFixed(2), muted:m.muted,
    buffered:ranges(m.buffered),
    err:m.error?{code:m.error.code,msg:(m.error.message||'').slice(0,120)}:null
  };
  if(m.tagName==='VIDEO'){
    o.w=m.videoWidth; o.h=m.videoHeight;
    try{var q=m.getVideoPlaybackQuality(); o.q={total:q.totalVideoFrames,dropped:q.droppedVideoFrames,corrupt:q.corruptedVideoFrames};}catch(e){}
  }
  return o;
}))
"""


def _decoder_threads():
    """GStreamer decode thread comms live in the WebProcess (droidvdec/vp9dec/...)."""
    procs = device.processes()
    found = {}
    for pid in procs["web"]:
        out = device.ssh(
            f"for t in /proc/{pid}/task/*/comm; do cat \"$t\" 2>/dev/null; done"
        ).stdout
        for comm in out.splitlines():
            cl = comm.strip().lower()
            if any(k in cl for k in ("dec", "droid", "vpx", "vp9", "vp8",
                                     "h264", "venus", "v4l", "omx", "gst")):
                found[comm.strip()] = found.get(comm.strip(), 0) + 1
    return found


def _print_elem(i, e):
    tag = ui.c(e["tag"], "bold", "cyan")
    print(f"\n  [{i}] {tag}  {ui.c(e['src'] or '(no src)', 'grey')}")
    ready = _READY[e["ready"]] if 0 <= e["ready"] < len(_READY) else e["ready"]
    net = _NET[e["net"]] if 0 <= e["net"] < len(_NET) else e["net"]
    rstyle = "green" if e["ready"] >= 3 else "yellow" if e["ready"] >= 1 else "red"
    state = "playing" if not e["paused"] and not e["ended"] else ("ended" if e["ended"] else "paused")
    ui.kv("state", f"{ui.c(state, 'green' if state=='playing' else 'yellow')}  "
                   f"ready={ui.c(ready, rstyle)}  net={net}")
    pos = f"{e['t']}s" + (f" / {e['dur']}s" if e["dur"] else "")
    ui.kv("position", f"{pos}  rate={e['rate']}  vol={e['vol']}{' muted' if e['muted'] else ''}")
    if e.get("w"):
        ui.kv("resolution", f"{e['w']}×{e['h']}")
    if e.get("q"):
        q = e["q"]
        dstyle = "red" if q["dropped"] else "green"
        ui.kv("decode frames", f"total={q['total']}  "
              f"{ui.c('dropped=' + str(q['dropped']), dstyle)}  corrupt={q['corrupt']}")
    if e.get("buffered"):
        ui.kv("buffered", str(e["buffered"]))
    if e.get("err"):
        ui.err(f"  media error code={e['err']['code']} {e['err']['msg']}")


async def _run(args):
    async with cdp.connect_session(match=getattr(args, "tab", None)) as s:
        url = await s.eval_value("location.href", default="?")
        ui.heading(f"media — {url}")
        snap1 = json.loads(await s.eval_value(_SNAP, default="[]"))
        if not snap1:
            ui.info("no <video>/<audio> elements on the page.")
        for i, e in enumerate(snap1):
            _print_elem(i, e)

        if args.watch and snap1:
            ui.info(f"\nwatching decode quality for {args.watch:.0f}s…")
            await asyncio.sleep(args.watch)
            snap2 = json.loads(await s.eval_value(_SNAP, default="[]"))
            print()
            for i, (a, b) in enumerate(zip(snap1, snap2)):
                if a.get("q") and b.get("q"):
                    dec = b["q"]["total"] - a["q"]["total"]
                    drop = b["q"]["dropped"] - a["q"]["dropped"]
                    fps = dec / args.watch
                    dt = b["t"] - a["t"]
                    dstyle = "red" if drop else "green"
                    print(f"  [{i}] decoded {ui.c(f'{fps:.1f} fps', 'bold')} "
                          f"({dec} frames), {ui.c(f'+{drop} dropped', dstyle)}, "
                          f"advanced {dt:.1f}s wall {args.watch:.0f}s")

    # engine side
    print()
    ui.heading("media — engine (GStreamer)")
    threads = _decoder_threads()
    if threads:
        ui.kv("decode threads", ", ".join(sorted(threads)))
        if any("droid" in t.lower() for t in threads):
            ui.info("droidvdec active → hardware decode path (H.264/H.265)")
        if any(("vp9" in t.lower() or "vpx" in t.lower()) for t in threads):
            ui.info("vp9/vpx active → software VP9 decode path")
    else:
        ui.info("no decode threads live (nothing decoding right now)")
    rank = device.ssh(
        "grep -oE 'GST_PLUGIN_FEATURE_RANK=[^ ]+' /proc/$(pgrep -f WPEWebProces[s] "
        "| head -1)/environ 2>/dev/null | tr '\\0' '\\n' | head -1").stdout.strip()
    if rank:
        ui.kv("feature rank", rank)
    logd = device.ssh(
        "grep -iE 'droidvdec|vp9|vp8|decodebin|GST_|video/' /tmp/atl.log 2>/dev/null "
        "| tail -8").stdout.strip()
    if logd:
        ui.kv("recent log", "")
        print(ui.c("    " + logd.replace("\n", "\n    "), "grey"))
    return 0


def run(args):
    return asyncio.run(_run(args))
