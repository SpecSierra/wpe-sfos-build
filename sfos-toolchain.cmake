set(_SFOS_SYSROOT "$ENV{SYSROOT}")
if(_SFOS_SYSROOT STREQUAL "")
    set(_SFOS_SYSROOT /opt/sfos-sysroot)
endif()

set(_WPE_PREFIX "$ENV{WPE_PREFIX}")
if(_WPE_PREFIX STREQUAL "")
    set(_WPE_PREFIX /opt/wpe-sfos)
endif()

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_SYSROOT "${_SFOS_SYSROOT}")
set(CMAKE_STAGING_PREFIX "${_WPE_PREFIX}")
set(CMAKE_FIND_ROOT_PATH "${_WPE_PREFIX}" "${_SFOS_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
add_compile_definitions(U_DISABLE_RENAMING=1)

# Target Snapdragon 665 = ARMv8.0-A. No LSE atomics (no casal/ldadd etc.),
# no dotprod, no fp16 arithmetic. -mno-outline-atomics forces call-based
# atomics rather than inline LSE instructions.
set(CMAKE_C_FLAGS   "${CMAKE_C_FLAGS}   -march=armv8-a -mno-outline-atomics")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=armv8-a -mno-outline-atomics")

if("$ENV{PKG_CONFIG_SYSROOT_DIR}" STREQUAL "")
    # The Qt5 bridge consumes pkg-config files from the staged WPE prefix, not
    # from the SFOS sysroot. Prefixing absolute include paths through a sysroot
    # turns /tmp or /opt/wpe-sfos entries into invalid /opt/sfos-sysroot/... paths.
    set(ENV{PKG_CONFIG_SYSROOT_DIR} "")
endif()

if("$ENV{PKG_CONFIG_PATH}" STREQUAL "")
    set(ENV{PKG_CONFIG_PATH} "${_WPE_PREFIX}/lib/pkgconfig:${_WPE_PREFIX}/lib/aarch64-linux-gnu/pkgconfig")
endif()

# Static-link libstdc++ and libgcc into every binary and shared lib.
# Eliminates GLIBCXX_3.4.29/30 version requirements and removes the need
# to deploy a patched libstdc++.so.6 to the device.
set(STATIC_RUNTIME_FLAGS "-static-libstdc++ -static-libgcc -Wl,--allow-shlib-undefined")
set(CMAKE_EXE_LINKER_FLAGS_INIT    "${STATIC_RUNTIME_FLAGS}")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${STATIC_RUNTIME_FLAGS}")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "${STATIC_RUNTIME_FLAGS}")
set(CMAKE_EXE_LINKER_FLAGS    "${CMAKE_EXE_LINKER_FLAGS}    ${STATIC_RUNTIME_FLAGS}")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${STATIC_RUNTIME_FLAGS}")
set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} ${STATIC_RUNTIME_FLAGS}")
