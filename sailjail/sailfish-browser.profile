# Sailfish OS sailjail (firejail) profile for sailfish-browser with WPE WebKit
# Place at: /etc/sailjail/applications/sailfish-browser.profile
#
# Differences from the stock Gecko profile:
#  - Allow WPE subprocess exec paths (/usr/libexec/wpewebkit/)
#  - Allow WPE / compat library directories
#  - Allow Wayland GPU / DRM device nodes needed by WPE backend
#  - Sandbox is NOT enforced until sailjail re-enablement is complete;
#    set Sandboxing=disabled below until all paths are verified.

[sailfish]
Sandboxing=disabled

# Once all paths are validated, switch to:
# Sandboxing=enabled
# and uncomment the whitelist entries below.

[X-Sailjail]
Permissions=Internet;Audio
OrganizationName=org.sailfishos
ApplicationName=sailfish-browser

# --- Whitelist (effective only when Sandboxing=enabled) ---

# Browser data
#whitelist=${HOME}/.local/share/sailfish-browser
#whitelist=${HOME}/.cache/sailfish-browser
#whitelist=${HOME}/Downloads

# WPE WebKit runtime libraries
#whitelist=/usr/lib64/libWPEWebKit-2.0.so.1
#whitelist=/usr/lib64/libWPEBackend-fdo-1.0.so.1
#whitelist=/usr/lib64/libwpe-1.0.so.1
#whitelist=/usr/lib64/libepoxy.so.0
#whitelist=/usr/lib64/libsoup-3.0.so.0
#whitelist=/usr/lib64/libharfbuzz-icu.so.0

# WPE compat shims
#whitelist=/usr/lib64/wpe-compat

# WPE Qt5 plugin
#whitelist=/usr/lib64/qt5/qml/org/wpewebkit

# WPE subprocess helpers
#whitelist=/usr/libexec/wpewebkit/WPEWebProcess
#whitelist=/usr/libexec/wpewebkit/WPENetworkProcess
#whitelist=/usr/libexec/wpewebkit/WPEGPUProcess
#whitelist=/usr/lib64/wpewebkit/libWPEInjectedBundle.so

# Wayland / GPU devices
#whitelist=/run/display/wayland-0
#whitelist=/dev/dri
#whitelist=/dev/ion

# TLS certificates
#whitelist=/etc/pki/tls/certs/ca-bundle.crt
#whitelist=/etc/ssl/certs

# GIO modules (for GNUTLS/TLS support in libsoup)
#whitelist=/usr/lib64/gio/modules
