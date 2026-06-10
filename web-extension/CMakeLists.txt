cmake_minimum_required(VERSION 3.18)
project(atlantic-adblock-extension LANGUAGES C)

include(GNUInstallDirs)

find_package(PkgConfig REQUIRED)
# The dedicated web-process-extension module; Requires glib-2.0 + libsoup-3.0, so
# soup/glib cflags and libs come in transitively (matches the proven qt5-plugin
# pattern, where glib resolves transitively via wpe-webkit-2.0).
pkg_check_modules(WPEExt REQUIRED IMPORTED_TARGET wpe-web-process-extension-2.0)

# Directory holding the Brave/Rust adblock shared library (libatlantic_adblock.so).
# The extension is dlopen'd into the WPEWebProcess, which does NOT otherwise link
# the Rust engine, so we link it by name (creating a DT_NEEDED of
# "libatlantic_adblock.so", resolved from /usr/lib64 at runtime).
if(NOT DEFINED ATLANTIC_ADBLOCK_LIBDIR)
    message(FATAL_ERROR "ATLANTIC_ADBLOCK_LIBDIR must point to the dir containing libatlantic_adblock.so")
endif()

add_library(atlantic-adblock-extension MODULE atlantic-adblock-extension.c)
set_target_properties(atlantic-adblock-extension PROPERTIES
    OUTPUT_NAME atlantic-adblock-extension
    PREFIX "lib")
target_compile_options(atlantic-adblock-extension PRIVATE -fvisibility=hidden)
target_link_directories(atlantic-adblock-extension PRIVATE "${ATLANTIC_ADBLOCK_LIBDIR}")
target_link_libraries(atlantic-adblock-extension PRIVATE
    PkgConfig::WPEExt
    atlantic_adblock)

install(TARGETS atlantic-adblock-extension
    DESTINATION "${CMAKE_INSTALL_LIBDIR}/atlantic-browser/web-extensions")
