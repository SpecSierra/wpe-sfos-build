Name:       libwpe
Summary:    WPE platform library for Sailfish OS
Version:    1.17.0
Release:    1
License:    BSD
URL:        https://github.com/WebPlatformForEmbedded/libwpe
# git archive --prefix=libwpe-1.17.0/ HEAD | xz > libwpe-1.17.0.tar.xz
Source0:    libwpe-%{version}.tar.xz
Source1:    sfos-meson-cross.ini

BuildRequires:  meson >= 0.55
BuildRequires:  ninja
BuildRequires:  gcc-c++
BuildRequires:  pkgconfig(xkbcommon)

%description
The libwpe library provides a generic API for WPE WebKit platform backends.
Built for Sailfish OS 5.0 aarch64 (Snapdragon 665, ARMv8.0-A).

%package devel
Summary:    Development files for libwpe
Requires:   %{name} = %{version}-%{release}

%description devel
Headers and pkg-config file for building against libwpe on Sailfish OS.

# ===========================================================================
%prep
%setup -q -n libwpe-%{version}

%build
meson setup build \
    --cross-file %{SOURCE1} \
    --prefix %{_prefix} \
    --buildtype release \
    -Dbuild-docs=false

ninja -C build %{?_smp_mflags}

%install
DESTDIR=%{buildroot} ninja -C build install

%post
/sbin/ldconfig || :

%postun
/sbin/ldconfig || :

%files
%{_libdir}/libwpe-1.0.so.*

%files devel
%{_libdir}/libwpe-1.0.so
%{_includedir}/wpe-1.0
%{_libdir}/pkgconfig/wpe-1.0.pc
