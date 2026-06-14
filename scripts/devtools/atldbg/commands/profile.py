"""profile — find slow JS functions on the page.

This build has the JSC sampling profiler compiled out (ENABLE_SAMPLING_PROFILER
OFF), so the inspector's ScriptProfiler/Timeline script records are empty.  Instead
we inject a build-independent *instrumentation* profiler: it wraps the main-thread
entry points (setTimeout/setInterval/requestAnimationFrame and every
addEventListener handler) plus the Event Timing API, measures wall-clock self-time
of each callback, and attributes it to the call-site stack frame that scheduled it.

That catches the usual jank culprits — slow timers, heavy rAF loops, expensive
scroll/touch/resize handlers — with function+location attribution, no rebuild
needed.  Pair it with `atldbg cpu` for native (non-JS) hotspots.
"""
from __future__ import annotations

import asyncio

from .. import cdp, ui

_INSTALL = r"""
(function(){
  if (window.__atldbg_prof) { window.__atldbg_prof.reset(); return 'rearmed'; }
  var data = {};
  function rec(label, s, dur){
    var k = label + ' @@ ' + s;
    var e = data[k] || (data[k] = {total:0,count:0,max:0,label:label,site:s});
    e.total += dur; e.count++; if (dur > e.max) e.max = dur;
  }
  function atldbg_site(){
    // Skip our own frames (all named atldbg_*) and pick the first real caller.
    // JSC frames look like  funcName@url:line:col  (url may be empty for eval).
    try {
      var lines = ((new Error()).stack || '').split('\n');
      for (var i=0;i<lines.length;i++){
        var l = lines[i].trim();
        if (!l) continue;
        var name = l.split('@')[0];
        if (name.indexOf('atldbg_') === 0) continue;   // our wrappers/helpers
        if (l === '@') continue;                        // anonymous internal frame
        return l.slice(0,140);
      }
    } catch(e){}
    return '(top-level)';
  }
  function atldbg_wrap(cb, label, s){
    if (typeof cb !== 'function') return cb;
    return function atldbg_wrapped(){
      var t = performance.now();
      try { return cb.apply(this, arguments); }
      finally { rec(label, s, performance.now() - t); }
    };
  }
  var _sT=window.setTimeout,_sI=window.setInterval,_rAF=window.requestAnimationFrame;
  window.setTimeout=function atldbg_setTimeout(cb){ var s=atldbg_site(); arguments[0]=atldbg_wrap(cb,'timeout',s); return _sT.apply(window,arguments); };
  window.setInterval=function atldbg_setInterval(cb){ var s=atldbg_site(); arguments[0]=atldbg_wrap(cb,'interval',s); return _sI.apply(window,arguments); };
  if(_rAF) window.requestAnimationFrame=function atldbg_raf(cb){ var s=atldbg_site(); return _rAF.call(window, atldbg_wrap(cb,'raf',s)); };
  var _ael=EventTarget.prototype.addEventListener, _rel=EventTarget.prototype.removeEventListener;
  EventTarget.prototype.addEventListener=function atldbg_addEventListener(type,cb,opts){
    if(typeof cb==='function'){ var s=atldbg_site(); var w=atldbg_wrap(cb,'on:'+type,s); try{cb.__atldbg_w=w;}catch(e){} return _ael.call(this,type,w,opts); }
    return _ael.apply(this,arguments);
  };
  EventTarget.prototype.removeEventListener=function atldbg_removeEventListener(type,cb,opts){
    if(typeof cb==='function' && cb.__atldbg_w){ return _rel.call(this,type,cb.__atldbg_w,opts); }
    return _rel.apply(this,arguments);
  };
  try {
    var po=new PerformanceObserver(function(list){
      list.getEntries().forEach(function(en){ rec('event:'+en.name,'(EventTiming)',en.duration); });
    });
    po.observe({entryTypes:['event']});
  } catch(e){}
  window.__atldbg_prof = {
    reset:function(){ data={}; },
    report:function(){
      return Object.keys(data).map(function(k){return data[k];})
        .sort(function(a,b){return b.total-a.total;}).slice(0,40);
    }
  };
  return 'installed';
})()
"""


async def _run(args):
    async with cdp.connect_session(match=getattr(args, "tab", None)) as s:
        url = await s.eval_value("location.href", default="?")
        ui.heading(f"profile — JS self-time on {url}")
        state = await s.eval_value(f"({_INSTALL})", default="?")
        ui.info(f"instrumentation {state}; interact with the page for {args.seconds:.0f}s "
                "(scroll, tap, trigger the slow path)…")
        await asyncio.sleep(args.seconds)
        rows = await s.eval_value("JSON.stringify(window.__atldbg_prof.report())",
                                  default="[]")
    import json
    rows = json.loads(rows) if isinstance(rows, str) else (rows or [])
    if not rows:
        ui.info("no instrumented callbacks fired — page was idle, or work ran "
                "outside timers/rAF/listeners (try `atldbg cpu` for native hotspots).")
        return 0

    print()
    print(f"  {'total ms':>9} {'calls':>6} {'avg':>7} {'max':>7}  callback / call-site")
    print("  " + ui.c("─" * 72, "grey"))
    for e in rows[: args.top]:
        total, n, mx = e["total"], e["count"], e["max"]
        avg = total / n if n else 0
        style = "red" if total >= 500 else "yellow" if total >= 100 else "green"
        label = ui.c(e["label"], "bold")
        site = ui.c(e["site"], "grey")
        print(f"  {ui.c(f'{total:9.1f}', style)} {n:6d} {avg:7.2f} {mx:7.1f}  {label}")
        print(f"  {'':>32}{site}")
    ui.info("'total ms' is wall-clock self-time inside the callback over the window.")
    return 0


def run(args):
    return asyncio.run(_run(args))
