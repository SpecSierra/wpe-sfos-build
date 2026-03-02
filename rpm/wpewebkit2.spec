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
Source4:    qt5-plugin-gnuinstalldirs.patch

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
  - VIDEO, MEDIA_STREAM, WEB_CODECS, WEB_AUDIO disabled (no GStreamer)
  - GEOLOCATION, SPEECH_SYNTHESIS, XSLT, WEBDRIVER disabled
  - Static libstdc++ / libgcc (no GLIBCXX version requirements)
  - glibc version tags downgraded to GLIBC_2.17

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
    -DENABLE_SPEECH_SYNTHESIS=OFF \
    -DENABLE_XSLT=OFF \
    -DENABLE_WEBDRIVER=OFF \
    -DENABLE_MEDIA_STREAM=OFF \
    -DENABLE_MEDIA_RECORDER=OFF \
    -DENABLE_WEB_CODECS=OFF \
    -DENABLE_BUBBLEWRAP_SANDBOX=OFF \
    -DENABLE_MINIBROWSER=OFF \
    -DENABLE_INTROSPECTION=OFF \
    -DUSE_GSTREAMER=OFF \
    -DUSE_GSTREAMER_GL=OFF \
    -DUSE_ATK=OFF \
    -DUSE_LCMS=OFF \
    -DUSE_LIBBACKTRACE=OFF \
    -DUSE_LIBHYPHEN=OFF \
    -DUSE_OPENJPEG=OFF \
    -DUSE_WOFF2=OFF \
    -DUSE_AVIF=OFF \
    -DUSE_SKIA=ON \
    -DUSE_SYSPROF_CAPTURE=ON \
    -DUSE_SYSTEM_SYSPROF_CAPTURE=NO

ninja -C WebKitBuild/Release %{?_smp_mflags}

%install
DESTDIR=%{buildroot} ninja -C WebKitBuild/Release install

# libWPEInjectedBundle.so is not installed by ninja install — copy manually
install -d %{buildroot}%{_libdir}/wpe-webkit-2.0
install -m 755 WebKitBuild/Release/lib/libWPEInjectedBundle.so \
    %{buildroot}%{_libdir}/wpe-webkit-2.0/libWPEInjectedBundle.so

# Patch GLIBC_2.34+ version tags down to GLIBC_2.17 in all installed binaries
python3 %{SOURCE3} \
    %{buildroot}%{_libdir}/libWPEWebKit-2.0.so.*.*.* \
    %{buildroot}%{_libdir}/wpe-webkit-2.0/libWPEInjectedBundle.so \
    %{buildroot}%{_libexecdir}/wpe-webkit-2.0/WPEWebProcess \
    %{buildroot}%{_libexecdir}/wpe-webkit-2.0/WPENetworkProcess \
    %{buildroot}%{_libexecdir}/wpe-webkit-2.0/WPEGPUProcess

%post
/sbin/ldconfig || :

%postun
/sbin/ldconfig || :

%files
%license Source/WebKit/LICENSE
%{_libdir}/libWPEWebKit-2.0.so.*
%dir %{_libdir}/wpe-webkit-2.0
%{_libdir}/wpe-webkit-2.0/libWPEInjectedBundle.so
%dir %{_libexecdir}/wpe-webkit-2.0
%{_libexecdir}/wpe-webkit-2.0/WPEWebProcess
%{_libexecdir}/wpe-webkit-2.0/WPENetworkProcess
%{_libexecdir}/wpe-webkit-2.0/WPEGPUProcess

%files devel
%{_libdir}/libWPEWebKit-2.0.so
%{_includedir}/wpe-webkit-2.0
%{_libdir}/pkgconfig/wpe-webkit-2.0.pc
