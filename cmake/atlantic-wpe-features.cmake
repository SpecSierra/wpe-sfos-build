# Shared Atlantic WebKit feature policy used by both the native build script
# and the rpmbuild/spec path.

set(ENABLE_VIDEO ON CACHE BOOL "" FORCE)
set(ENABLE_MEDIA_STREAM ON CACHE BOOL "" FORCE)
set(ENABLE_MEDIA_RECORDER OFF CACHE BOOL "" FORCE)
set(ENABLE_WEB_CODECS OFF CACHE BOOL "" FORCE)
set(ENABLE_WEB_AUDIO ON CACHE BOOL "" FORCE)
set(ENABLE_GEOLOCATION OFF CACHE BOOL "" FORCE)
set(ENABLE_GAMEPAD OFF CACHE BOOL "" FORCE)
set(ENABLE_SPELLCHECK OFF CACHE BOOL "" FORCE)
set(ENABLE_SPEECH_SYNTHESIS OFF CACHE BOOL "" FORCE)
set(ENABLE_SAMPLING_PROFILER OFF CACHE BOOL "" FORCE)
set(ENABLE_INTROSPECTION OFF CACHE BOOL "" FORCE)
set(ENABLE_WEBDRIVER OFF CACHE BOOL "" FORCE)
set(ENABLE_XSLT OFF CACHE BOOL "" FORCE)
set(ENABLE_BUBBLEWRAP_SANDBOX OFF CACHE BOOL "" FORCE)

set(USE_ATK OFF CACHE BOOL "" FORCE)
set(USE_GSTREAMER ON CACHE BOOL "" FORCE)

# WebKit 2.52.3 in this tree registers webkitwebsrc, but does not expose a
# USE_GSTREAMER_WEBKIT_HTTP_SRC CMake toggle to force here.

# Keep GL integration off for now: hybris EGL in the WPEWebProcess subprocess
# has historically been unstable on SFOS. Revisit when subprocesses are stable.
# set(USE_GSTREAMER_GL ON CACHE BOOL "" FORCE)
set(USE_GSTREAMER_GL OFF CACHE BOOL "" FORCE)

# Enable Media Source Extensions (MSE) — required for YouTube, Twitch, etc.
# MSE-based players do not use GStreamer HTTP source directly; they push buffers
# via JS. MSE is already implicitly enabled via ENABLE_VIDEO but make it explicit.
set(ENABLE_MEDIA_SOURCE ON CACHE BOOL "" FORCE)

# Enable adaptive bitrate streaming support
set(ENABLE_VIDEO_TRACK ON CACHE BOOL "" FORCE)

set(USE_LCMS OFF CACHE BOOL "" FORCE)
set(USE_LIBBACKTRACE OFF CACHE BOOL "" FORCE)
set(USE_LIBHYPHEN OFF CACHE BOOL "" FORCE)
set(USE_OPENJPEG OFF CACHE BOOL "" FORCE)
set(USE_WOFF2 ON CACHE BOOL "" FORCE)
set(USE_AVIF OFF CACHE BOOL "" FORCE)
set(USE_SYSTEM_SYSPROF_CAPTURE OFF CACHE BOOL "" FORCE)
