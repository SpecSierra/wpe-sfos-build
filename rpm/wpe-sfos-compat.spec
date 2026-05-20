Name:       wpe-sfos-compat
Summary:    SFOS compatibility shims for WPE WebKit
Version:    1.0.0
Release:    1
License:    LGPL-2.1+
URL:        https://github.com/SpecSierra/wpe-sfos-build
# Create with: git archive --prefix=wpe-sfos-compat-1.0.0/ HEAD | bzip2 > wpe-sfos-compat-1.0.0.tar.bz2
# Run from inside the wpe-sfos-build git repo root.
Source0:    %{name}-%{version}.tar.bz2

BuildRequires:  gcc

%description
Compatibility shim libraries historically used to run Atlantic WPE builds on
older Sailfish OS baselines. The current SFOS 5.1 default path keeps this
package explicit and temporary rather than treating it as the normal runtime.

Provides:
  - glibc 2.31+ symbol stubs missing from SFOS glibc 2.30
  - SIGILL skip handler for ARMv8.1+ CPU feature probes
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
$CC $CFLAGS $SHARED -o libsigill_skip.so         libsigill_skip.c
$CC $CFLAGS $SHARED -o libegl-stubs.so           libegl-stubs.c

%install
install -d %{buildroot}%{_libdir}/wpe-compat

for lib in \
    libglibc-compat.so \
    libsigill_skip.so \
    libegl-stubs.so; do
    install -m 755 $lib %{buildroot}%{_libdir}/wpe-compat/$lib
done

# Environment file: sets LD_PRELOAD for all nemo/user sessions
install -d %{buildroot}%{_sharedstatedir}/environment/nemo
. ./versions.env
. ./deploy/runtime-common.sh
compat_preload="$(atlantic_build_ld_preload)"
compat_library_path="$(atlantic_default_library_path)"
python3 ./scripts/write-runtime-env.py \
    %{buildroot}%{_sharedstatedir}/environment/nemo/70-wpe-compat.conf \
    --comment "WPE SFOS compatibility shims — loaded for all nemo user sessions." \
    --entry LD_LIBRARY_PATH "${compat_library_path}" \
    --optional-entry LD_PRELOAD "${compat_preload}"

%post
/sbin/ldconfig || :

%postun
/sbin/ldconfig || :

%files
%license LICENSE
%dir %{_libdir}/wpe-compat
%{_libdir}/wpe-compat/libglibc-compat.so
%{_libdir}/wpe-compat/libsigill_skip.so
%{_libdir}/wpe-compat/libegl-stubs.so
%{_sharedstatedir}/environment/nemo/70-wpe-compat.conf
