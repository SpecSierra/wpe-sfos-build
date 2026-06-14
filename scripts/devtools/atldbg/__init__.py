"""atldbg — Atlantic Browser debugger.

A single, powerful host-side tool for debugging the WPE-WebKit Atlantic browser
running on the SFOS dev device: find bugs (console/exceptions/network), find what
is executing (per-thread CPU sampling), find slow functions (JS sampling
profiler), and debug media (video/audio) and rendering (fps/paint/layers).

Built on the existing remote-inspector client (wkinspector.Inspector) and device
access lore (README "Device access").
"""

__version__ = "1.0.0"
