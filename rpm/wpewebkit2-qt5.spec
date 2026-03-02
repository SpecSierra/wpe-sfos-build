Name:       wpewebkit2-qt5
Summary:    Qt5 QML plugin for WPE WebKit 2.50.5
Version:    2.50.5
Release:    1
License:    LGPLv2+
URL:        https://wpewebkit.org
# Source is the qt5/ subdirectory inside the wpewebkit tarball.
# Extract with: tar -xf wpewebkit-2.50.5.tar.xz
#   wpewebkit-2.50.5/Source/WebKit/UIProcess/API/wpe/qt5/
Source0:    wpewebkit-%{version}.tar.xz
Source1:    sfos-toolchain.cmake

BuildRequires:  cmake >= 3.20
BuildRequires:  ninja
BuildRequires:  gcc-c++
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Gui)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(wpewebkit-2.0)
BuildRequires:  pkgconfig(wpe-1.0)
BuildRequires:  pkgconfig(glib-2.0)

Requires:   wpewebkit2 = %{version}
Requires:   sailfishsilica-qt5

%description
Qt5 QML plugin (org.wpewebkit.qtwpe) for embedding WPE WebKit web views
into Qt Quick / Silica applications on Sailfish OS.

Installs:
  /usr/lib64/qt5/qml/org/wpewebkit/qtwpe/libqtwpe.so
  /usr/lib64/qt5/qml/org/wpewebkit/qtwpe/qmldir

Import in QML:
  import org.wpewebkit.qtwpe 1.0

# ===========================================================================
%prep
%setup -q -n wpewebkit-%{version}

%build
cd Source/WebKit/UIProcess/API/wpe/qt5
cmake -B build -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE=%{SOURCE1} \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=%{_prefix}
ninja -C build %{?_smp_mflags}

%install
cd Source/WebKit/UIProcess/API/wpe/qt5
DESTDIR=%{buildroot} ninja -C build install

%post
/sbin/ldconfig || :

%postun
/sbin/ldconfig || :

%files
%dir %{_libdir}/qt5/qml/org/wpewebkit
%dir %{_libdir}/qt5/qml/org/wpewebkit/qtwpe
%{_libdir}/qt5/qml/org/wpewebkit/qtwpe/libqtwpe.so
%{_libdir}/qt5/qml/org/wpewebkit/qtwpe/qmldir
