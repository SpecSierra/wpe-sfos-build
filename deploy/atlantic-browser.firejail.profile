# Atlantic Browser — Sailjail-style confinement profile (applied via firejail).
#
# WHY firejail directly and not sailjaild:
#   Sailjail always prepends the mandatory Base.permission, which does
#   `caps.drop all`.  That is terminal — a later `caps.keep` cannot re-grant a
#   capability (verified on host: caps.drop all → nested bwrap fails with
#   "Creating new namespace failed", in both command-line and profile-include
#   form).  The WebKit bubblewrap sandbox (WPEWebProcess) needs CAP_SYS_ADMIN to
#   create its nested user namespace, so we must retain that capability — which
#   is only possible by composing our own firejail profile instead of going
#   through sailjaild's Base.
#
# SECURITY TRADE-OFF (intentional, opt-in):
#   Retaining CAP_SYS_ADMIN in the outer sandbox significantly weakens the
#   confinement of the browser UI process — it is close to root-equivalent.
#   The untrusted web *content* still runs in the inner bwrap sandbox (with caps
#   dropped there).  This profile is gated behind ATLANTIC_ENABLE_SAILJAIL=1 and
#   is OFF by default.
#
# STAGE: this is the bring-up profile.  It establishes the privilege posture
#   that allows nesting plus a sensible blacklist baseline, but keeps the
#   filesystem broadly readable so the WPE runtime keeps working.  Tightening to
#   an explicit whitelist is the on-device follow-up (use `firejail --debug` to
#   discover denied paths).  THIS HAS NOT BEEN VALIDATED ON A DEVICE YET.

# ── privilege posture (the proven nested-bwrap recipe) ──────────────────────
# Retain only CAP_SYS_ADMIN (needed for nested user namespaces); drop the rest.
caps.keep sys_admin
nonewprivs
seccomp

# ── sensible baseline blacklists (firejail-shipped) ─────────────────────────
# CRITICAL: disable-common.inc does `blacklist ${PATH}/bwrap` (it treats bwrap
# as a SUID sandbox-escape vector).  That makes /usr/bin/bwrap un-executable
# inside the sandbox — exactly the binary the nested WebKit sandbox must run.
# Un-blacklist it (and xdg-dbus-proxy, which bwrap spawns) BEFORE the include.
noblacklist ${PATH}/bwrap
noblacklist ${PATH}/xdg-dbus-proxy
include disable-common.inc

# ── keep the Atlantic / WPE runtime readable ────────────────────────────────
# (noblacklist guards against disable-common.inc hiding anything we need; we do
#  NOT switch to a whitelist model yet — that is the device-tuning step.)
noblacklist /opt/wpe-sfos
noblacklist /usr/libexec/wpe-webkit-2.0
noblacklist /usr/lib64/wpe-compat
noblacklist /usr/share/atlantic-browser
noblacklist ${HOME}/.local/share/atlantic-browser
noblacklist ${HOME}/.cache/atlantic-browser
noblacklist ${HOME}/.config/atlantic-browser

# ── GPU / Wayland (libhybris / Adreno) ──────────────────────────────────────
# Do NOT use private-dev: it would hide the Android GPU nodes (/dev/kgsl-3d0,
# /dev/ion, /dev/dri) the WPE GPU path needs — same black-screen failure mode
# guarded against in the bubblewrap launcher patch.  The host /dev is left
# intact here on purpose.
