# devtools — on-device debugging helpers

Host-side helper scripts used during browser development on the build server.
They are **not** part of any build or RPM — purely manual debugging aids.

## Touch input simulation

The device has no `evdev`/`evemu` tools, so touch is simulated by raw-writing
events to `/dev/input/event2` (the `sec_touchscreen`, a type-B multitouch device
whose ABS range maps 1:1 to pixels). These run **on the device** (`devel-su -p`,
which keeps the session env and runs as `defaultuser`, already in the `input`
group — no real root needed).

| Script | Usage |
|--------|-------|
| `tap.py X Y [hold_seconds]` | single tap at pixel (X, Y); default hold 0.08s |
| `swipe.py X1 Y1 X2 Y2` | drag/flick over ~20 steps |
| `evtouch.py` | shared module (constants + `Touch` class) |

> **Copy `evtouch.py` to the device alongside `tap.py`/`swipe.py`** — they
> `import evtouch`, so all three must land in the same directory.

## Remote Web Inspector (Target-wrapped protocol)

These run on the **build host** and drive the WPE inspector WebSocket. They need
a tunnel to the device: `ssh -L 9224:127.0.0.1:9224 ...`, and the browser must be
launched with `WEBKIT_INSPECTOR_HTTP_SERVER=0.0.0.0:9224`.

| Script | Purpose |
|--------|---------|
| `wkinspector.py` | shared client: connect, target discovery, wrap/unwrap |
| `wkeval.py "<js>"` | evaluate JS on the page target, print the result |
| `wkinspect.py "<js>" [--gesture]` | same, with optional user-gesture emulation |
| `wkconsole.py` | dump buffered console messages |
| `wkdump.py "<js>"` | enable Runtime, evaluate, dump all frames for a few seconds |
| `wkprobe.py "<js>"` | low-level raw-frame probe (direct vs wrapped protocol) |

`wkeval`/`wkinspect`/`wkconsole`/`wkdump` build on the `Inspector` class in
`wkinspector.py`; `wkprobe.py` works with raw frames and only shares the
connection constants.
