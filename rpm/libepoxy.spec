Name:       libepoxy
Summary:    GL dispatch library for Sailfish OS
Version:    1.5.11
Release:    1
License:    MIT
URL:        https://github.com/anholt/libepoxy
# git archive --prefix=libepoxy-1.5.11/ HEAD | xz > libepoxy-1.5.11.tar.xz
Source0:    libepoxy-%{version}.tar.xz
Source1:    sfos-meson-cross.ini

BuildRequires:  meson >= 0.54
BuildRequires:  ninja
BuildRequires:  gcc
BuildRequires:  python3

%description
libepoxy is a library for handling OpenGL function pointer management.
Built for Sailfish OS 5.0 aarch64 (Snapdragon 665, ARMv8.0-A).

%package devel
Summary:    Development files for libepoxy
Requires:   %{name} = %{version}-%{release}

%description devel
Headers and pkg-config file for building against libepoxy on Sailfish OS.

# ===========================================================================
%prep
%setup -q -n libepoxy-%{version}

%build
meson setup build \
    --cross-file %{SOURCE1} \
    --prefix %{_prefix} \
    --buildtype release \
    -Ddocs=false \
    -Dtests=false \
    -Degl=yes \
    -Dglx=no \
    -Dx11=false

ninja -C build %{?_smp_mflags}

%install
DESTDIR=%{buildroot} ninja -C build install

%post
/sbin/ldconfig || :

%postun
/sbin/ldconfig || :

%files
%{_libdir}/libepoxy.so.*

%files devel
%{_libdir}/libepoxy.so
%{_includedir}/epoxy
%{_libdir}/pkgconfig/epoxy.pc
