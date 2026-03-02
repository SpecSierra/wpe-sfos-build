Name:       wpebackend-fdo
Summary:    WPE backend using freedesktop.org stack for Sailfish OS
Version:    1.17.0
Release:    1
License:    BSD
URL:        https://github.com/igalia/WPEBackend-fdo
# git archive --prefix=wpebackend-fdo-1.17.0/ HEAD | xz > wpebackend-fdo-1.17.0.tar.xz
Source0:    wpebackend-fdo-%{version}.tar.xz
Source1:    sfos-meson-cross.ini

BuildRequires:  meson >= 0.52
BuildRequires:  ninja
BuildRequires:  gcc-c++
BuildRequires:  pkgconfig(libwpe-1.0) >= 1.9.0
BuildRequires:  pkgconfig(epoxy)
BuildRequires:  pkgconfig(wayland-client)
BuildRequires:  pkgconfig(wayland-server)
BuildRequires:  pkgconfig(glib-2.0)

Requires:   libwpe
Requires:   libepoxy

%description
WPEBackend-fdo provides a WPE backend based on the freedesktop.org stack
(Wayland, EGL/DRM). Built for Sailfish OS 5.0 aarch64 (Snapdragon 665).

%package devel
Summary:    Development files for wpebackend-fdo
Requires:   %{name} = %{version}-%{release}

%description devel
Headers and pkg-config file for building against WPEBackend-fdo on Sailfish OS.

# ===========================================================================
%prep
%setup -q -n wpebackend-fdo-%{version}

%build
meson setup build \
    --cross-file %{SOURCE1} \
    --prefix %{_prefix} \
    --buildtype release

ninja -C build %{?_smp_mflags}

%install
DESTDIR=%{buildroot} ninja -C build install

%post
/sbin/ldconfig || :

%postun
/sbin/ldconfig || :

%files
%{_libdir}/libWPEBackend-fdo-1.0.so.*

%files devel
%{_libdir}/libWPEBackend-fdo-1.0.so
%{_includedir}/wpe/fdo.h
%{_includedir}/wpe/fdo-egl.h
%{_includedir}/wpe/unstable
%{_libdir}/pkgconfig/wpebackend-fdo-1.0.pc
