Name:       wpewebkit2
Summary:    WPE WebKit 2.50.5 for Sailfish OS
Version:    2.50.5
Release:    1
License:    LGPLv2+ and BSD and MPLv2.0
URL:        https://wpewebkit.org
# Download from: https://wpewebkit.org/release/wpewebkit-2.50.5.tar.xz
Source0:    wpewebkit-%{version}.tar.xz
Source1:    sfos-toolchain.cmake
Source2:    webkit-quirks-no-video.patch
Source3:    patch-glibc-versions.py

BuildRequires:  cmake >= 3.20
BuildRequires:  ninja
BuildRequires:  gcc-c++
BuildRequires:  python3
BuildRequires:  perl
BuildRequires:  gperf
BuildRequires:  ruby
BuildRequires:  pkgconfig(glib-2.0)
BuildRequires:  pkgconfig(gio-2.0)
BuildRequires:  pkgconfig(gobject-2.0)
BuildRequires:  pkgconfig(libsoup-3.0)
BuildRequires:  pkgconfig(cairo)
BuildRequires:  pkgconfig(fontconfig)
BuildRequires:  pkgconfig(freetype2)
BuildRequires:  pkgconfig(harfbuzz)
BuildRequires:  pkgconfig(icu-uc)
BuildRequires:  pkgconfig(libjpeg)
BuildRequires:  pkgconfig(libpng)
BuildRequires:  pkgconfig(libwebp)
BuildRequires:  pkgconfig(sqlite3)
BuildRequires:  pkgconfig(zlib)
BuildRequires:  pkgconfig(wayland-client)
BuildRequires:  pkgconfig(wayland-server)
BuildRequires:  pkgconfig(xkbcommon)
BuildRequires:  pkgconfig(libwpe-1.0)
BuildRequires:  pkgconfig(wpebackend-fdo-1.0)
BuildRequires:  pkgconfig(epoxy)

# Runtime: WPE subprocesses are exec'd by the main process
Requires:       wpe-sfos-compat

%description
WPE WebKit 2.50.5 built for Sailfish OS 5.0 aarch64 (Snapdragon 665,
ARMv8.0-A). This is the engine used by the WPE Sailfish Browser as a
replacement for the Gecko/EmbedLite engine.

Build configuration:
  - VIDEO disabled (no GStreamer dependency)
  - WEB_AUDIO disabled
  - GEOLOCATION disabled
  - Static libstdc++ / libgcc (no GLIBCXX version requirements)
  - glibc version tags patched to GLIBC_2.28

%package devel
Summary:    Development files for WPE WebKit 2.50.5
Requires:   %{name} = %{version}-%{release}

%description devel
Headers and pkg-config file for building against WPE WebKit 2.50.5
on Sailfish OS.

# ===========================================================================
%prep
%setup -q -n wpewebkit-%{version}
patch -p1 < %{SOURCE2}

%build
cmake -B WebKitBuild/Release -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE=%{SOURCE1} \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=%{_prefix} \
    -DPORT=WPE \
    -DENABLE_VIDEO=OFF \
    -DENABLE_WEB_AUDIO=OFF \
    -DENABLE_GEOLOCATION=OFF \
    -DENABLE_GAMEPAD=OFF \
    -DENABLE_SPELLCHECK=OFF \
    -DENABLE_SAMPLING_PROFILER=OFF \
    -DUSE_GSTREAMER=OFF \
    -DUSE_LIBHYPHEN=OFF \
    -DUSE_OPENJPEG=OFF \
    -DUSE_WOFF2=OFF \
    -DUSE_AVIF=OFF \
    -DENABLE_MINIBROWSER=OFF \
    -DENABLE_INTROSPECTION=OFF

ninja -C WebKitBuild/Release %{?_smp_mflags}

%install
DESTDIR=%{buildroot} ninja -C WebKitBuild/Release install

# Patch GLIBC version tags in all installed .so files
find %{buildroot}%{_libdir} -name "*.so*" -type f | while read f; do
    python3 %{SOURCE3} "$f" || true
done

# WPE subprocess helper binaries go to libexec
install -d %{buildroot}%{_libexecdir}/wpewebkit
for bin in WPEWebProcess WPENetworkProcess WPEGPUProcess; do
    if [ -f WebKitBuild/Release/bin/$bin ]; then
        install -m 755 WebKitBuild/Release/bin/$bin \
            %{buildroot}%{_libexecdir}/wpewebkit/$bin
    fi
done

# InjectedBundle goes next to the helpers
install -d %{buildroot}%{_libdir}/wpewebkit
if [ -f WebKitBuild/Release/lib/libWPEInjectedBundle.so ]; then
    install -m 755 WebKitBuild/Release/lib/libWPEInjectedBundle.so \
        %{buildroot}%{_libdir}/wpewebkit/libWPEInjectedBundle.so
fi

%post
/sbin/ldconfig || :

%postun
/sbin/ldconfig || :

%files
%license Source/WebKit/LICENSE
%{_libdir}/libWPEWebKit-2.0.so.*
%{_libdir}/libWPEBackend-fdo-1.0.so.*
%{_libdir}/libwpe-1.0.so.*
%{_libdir}/libepoxy.so.*
%{_libdir}/libsoup-3.0.so.*
%{_libdir}/libharfbuzz-icu.so.*
%dir %{_libdir}/wpewebkit
%{_libdir}/wpewebkit/libWPEInjectedBundle.so
%dir %{_libexecdir}/wpewebkit
%{_libexecdir}/wpewebkit/WPEWebProcess
%{_libexecdir}/wpewebkit/WPENetworkProcess
%{_libexecdir}/wpewebkit/WPEGPUProcess

%files devel
%{_libdir}/libWPEWebKit-2.0.so
%{_libdir}/libWPEBackend-fdo-1.0.so
%{_libdir}/libwpe-1.0.so
%{_libdir}/libepoxy.so
%{_libdir}/libsoup-3.0.so
%{_includedir}/wpe-webkit-2.0
%{_includedir}/wpe-1.0
%{_libdir}/pkgconfig/wpewebkit-2.0.pc
%{_libdir}/pkgconfig/wpe-1.0.pc
%{_libdir}/pkgconfig/wpebackend-fdo-1.0.pc
%{_libdir}/pkgconfig/epoxy.pc
