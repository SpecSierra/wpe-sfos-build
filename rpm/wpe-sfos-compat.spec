Name:       wpe-sfos-compat
Summary:    SFOS compatibility shims for WPE WebKit
Version:    1.0.0
Release:    1
License:    LGPL-2.1+
URL:        https://github.com/SpecSierra/wpe-sfos-build
Source0:    %{name}-%{version}.tar.bz2

BuildRequires:  gcc

%description
Compatibility shim libraries required to run WPE WebKit 2.50.5 on
Sailfish OS 5.0 (glibc 2.28, ARMv8.0-A, Snapdragon 665).

Provides:
  - glibc 2.29+ symbol stubs missing from SFOS glibc 2.28
  - getauxval() fix for AT_HWCAP2 / AT_MINSIGSTKSZ on aarch64
  - SIGILL skip handler for ARMv8.1+ CPU feature probes
  - execve() wrapper to rewrite WPE subprocess paths under sailjail
  - EGL stub entry points for libepoxy load-time probing
  - C++ ABI / stdlibc++ compatibility layer

All shims are loaded via LD_PRELOAD through the browser environment
file (%{_sharedstatedir}/environment/nemo/70-wpe-compat.conf).

# ---------------------------------------------------------------------------
%package -n wpe-sfos-compat-devel
Summary:    Development headers for wpe-sfos-compat (unused; placeholder)
Requires:   %{name} = %{version}-%{release}
%description -n wpe-sfos-compat-devel
Placeholder devel sub-package.

# ===========================================================================
%prep
%setup -q -n %{name}-%{version}

%build
SYSROOT=%{_prefix}
CC="gcc"
CFLAGS="-O2 -march=armv8-a -fPIC -fvisibility=hidden"
SHARED="-shared -Wl,--allow-shlib-undefined"

$CC $CFLAGS $SHARED -o libglibc-compat.so       libglibc-compat.c
$CC $CFLAGS $SHARED -o libgetauxval_fix.so       libgetauxval_fix.c
$CC $CFLAGS $SHARED -o libgetauxval_fix2.so      libgetauxval_fix2.c
$CC $CFLAGS $SHARED -o libsigill_skip.so         libsigill_skip.c
$CC $CFLAGS $SHARED -o libsigill_skip2.so        libsigill_skip2.c
$CC $CFLAGS $SHARED -o libsigill_skip3.so        libsigill_skip3.c
$CC $CFLAGS $SHARED -o libexecve_wrap.so         libexecve_wrap.c  -ldl
$CC $CFLAGS $SHARED -o libexecve_wrap2.so        libexecve_wrap2.c -ldl
$CC $CFLAGS $SHARED -o libegl-stubs.so           libegl-stubs.c

%install
install -d %{buildroot}%{_libdir}/wpe-compat

for lib in \
    libglibc-compat.so \
    libgetauxval_fix.so \
    libgetauxval_fix2.so \
    libsigill_skip.so \
    libsigill_skip2.so \
    libsigill_skip3.so \
    libexecve_wrap.so \
    libexecve_wrap2.so \
    libegl-stubs.so; do
    install -m 755 $lib %{buildroot}%{_libdir}/wpe-compat/$lib
done

# Environment file: sets LD_PRELOAD for all nemo/user sessions
install -d %{buildroot}%{_sharedstatedir}/environment/nemo
cat > %{buildroot}%{_sharedstatedir}/environment/nemo/70-wpe-compat.conf << 'EOF'
# WPE SFOS compatibility shims — loaded for all user processes.
# Order matters: glibc-compat first, then getauxval, then sigill, then egl.
LD_PRELOAD=/usr/lib64/wpe-compat/libglibc-compat.so:/usr/lib64/wpe-compat/libgetauxval_fix.so:/usr/lib64/wpe-compat/libsigill_skip.so:/usr/lib64/wpe-compat/libegl-stubs.so
EOF

%post
/sbin/ldconfig || :

%postun
/sbin/ldconfig || :

%files
%license LICENSE
%dir %{_libdir}/wpe-compat
%{_libdir}/wpe-compat/libglibc-compat.so
%{_libdir}/wpe-compat/libgetauxval_fix.so
%{_libdir}/wpe-compat/libgetauxval_fix2.so
%{_libdir}/wpe-compat/libsigill_skip.so
%{_libdir}/wpe-compat/libsigill_skip2.so
%{_libdir}/wpe-compat/libsigill_skip3.so
%{_libdir}/wpe-compat/libexecve_wrap.so
%{_libdir}/wpe-compat/libexecve_wrap2.so
%{_libdir}/wpe-compat/libegl-stubs.so
%{_sharedstatedir}/environment/nemo/70-wpe-compat.conf
