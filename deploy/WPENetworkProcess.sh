#!/bin/sh
export LD_PRELOAD=/usr/lib64/wpe-compat/libglibc-compat.so:/usr/lib64/wpe-compat/libcow_string_compat.so:/usr/lib64/wpe-compat/libsigill_skip.so
export LD_LIBRARY_PATH=/usr/lib64/wpe-compat:/usr/lib64
export XDG_RUNTIME_DIR=/run/user/100000
export WAYLAND_DISPLAY=../../display/wayland-0
export GST_PLUGIN_SYSTEM_PATH_1_0=/usr/lib64/gstreamer-1.0
export GST_PLUGIN_PATH=/usr/lib64/gstreamer-1.0
exec /usr/libexec/wpe-webkit-2.0/WPENetworkProcess $@
