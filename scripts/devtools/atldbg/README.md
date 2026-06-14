# atldbg — Atlantic Browser debugger

One host-side tool to debug the WPE-WebKit Atlantic browser on the SFOS dev
device: **find bugs**, **find what's executing**, **find slow functions**, and
**debug media & rendering** — without remembering the ssh / dbus / tunnel lore.

```sh
./atldbg <command> [options]          # from scripts/devtools/
~/atldbg <command> [options]          # convenience symlink on the build host
```

It builds on the existing remote-inspector client (`../wkinspector.py`) and
centralises all device access (ssh, lipstick session bus, screenshots, launch,
inspector SSH tunnel) in `device.py`. **The inspector tunnel is opened
automatically** for every command that needs it — you never set up `-L 9224`
by hand.

## Quick start

```sh
~/atldbg launch https://jolla.com   # (re)start the browser WITH the inspector
~/atldbg doctor                     # one-shot health snapshot — run this first
~/atldbg cpu -s 5                   # what's burning CPU (scroll while it runs)
~/atldbg profile -s 15              # which JS callbacks are slow (interact)
~/atldbg media -w 5                 # video/audio + decode quality over 5s
~/atldbg render --scroll            # frame pacing / jank + screenshot
~/atldbg bug                        # live console errors / exceptions / net fails
```

## Commands

| Command | What it answers |
|---------|-----------------|
| `doctor` | Is everything healthy *right now*? procs, memory, CPU, page state, JS errors, media — all in one snapshot. Start here. |
| `bug [-s N] [-e]` | **Find bugs.** Live stream of console messages, uncaught JS exceptions (with call stack), and failed network loads. Detects WebProcess crashes during the window. `-e` = errors only. |
| `cpu [-s N]` | **Find exec usage.** Per-thread native CPU sampling (`/proc/<pid>/task/*/stat`) across UI/Web/Network/GPU processes — names the hot thread (compositor, JSC GC, Skia raster, droidvdec…). |
| `profile [-s N]` | **Find slow functions.** JS self-time profiler with `file:line:col` attribution. (This build compiles out the JSC sampling profiler, so this uses build-independent instrumentation of timers / rAF / event handlers + the Event Timing API.) |
| `media [-w N]` | **Debug video/audio.** Every `<video>/<audio>`: source, ready/network state, buffered, errors, and decode quality (total/dropped/corrupt frames). `-w N` reports decoded-fps and dropped-frame growth. Plus engine side: live GStreamer decode threads + feature rank. |
| `render [-s N] [--scroll]` | **Debug rendering.** Frame pacing via an injected rAF meter: fps, p50/p95 frame time, jank. `--scroll` auto-scrolls to exercise the raster/paint path. Samples render-thread CPU and grabs a screenshot to eyeball tile corruption. |
| `eval "<js>"` | Evaluate JS on the page and print the result. |
| `tabs` | List inspectable tabs (one websocket endpoint each). |
| `launch [url]` / `open <url>` | (Re)start the browser with the inspector / navigate it. |
| `shot [path]` / `log [-n N]` / `ps` | Screenshot / tail the browser log / list browser processes. |

## Multi-tab awareness (`--tab`)

Each tab is a *separate* inspector websocket endpoint. By default every
inspector command targets the **visible** tab — background tabs are
`document.hidden=true` under the engine's visibility throttling, which also
suspends their `rAF`, so debugging the wrong tab silently measures nothing.
Override with `--tab <url-substring>`, e.g. `atldbg profile --tab jolla`.

## How it works (and build-specific gotchas baked in)

- **No CDP sampling profiler.** `ENABLE_SAMPLING_PROFILER` is forced OFF in the
  Atlantic build, so `ScriptProfiler`/`Timeline` script records come back empty.
  `profile` therefore instruments the JS entry points itself.
- **Timeline timestamps are 0** in this build, so `render` measures frames with
  in-page `performance.now()` via `requestAnimationFrame`, not Timeline records.
- **rAF is compositor-driven**, so it only ticks while the page is visible *and*
  something is being rendered. `render` warns when the tab is hidden and
  `--scroll` provides the damage to measure against.

## Files

```
atldbg/
  __main__.py        CLI dispatch (python3 -m atldbg)
  device.py          ssh / dbus / screenshot / launch / inspector tunnel
  cdp.py             session, domain enable, event pump, tab selection
  ui.py              terminal colour / tables / bars
  commands/          doctor, bug, cpu, profile, media, render, misc
../atldbg.sh         launcher (sets PYTHONPATH); ~/atldbg symlinks to it
```
