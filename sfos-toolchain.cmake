set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_SYSROOT /opt/sfos-sysroot)
set(CMAKE_STAGING_PREFIX /opt/wpe-sfos)
set(CMAKE_FIND_ROOT_PATH /opt/wpe-sfos /opt/sfos-sysroot)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
add_compile_definitions(U_DISABLE_RENAMING=1)

# Target Snapdragon 665 = ARMv8.0-A. No LSE atomics (no casal/ldadd etc.),
# no dotprod, no fp16 arithmetic. -mno-outline-atomics forces call-based
# atomics rather than inline LSE instructions.
set(CMAKE_C_FLAGS   "${CMAKE_C_FLAGS}   -march=armv8-a -mno-outline-atomics")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=armv8-a -mno-outline-atomics")
set(ENV{PKG_CONFIG_SYSROOT_DIR} /opt/sfos-sysroot)
set(ENV{PKG_CONFIG_PATH} /opt/sfos-sysroot/usr/lib64/pkgconfig:/opt/wpe-sfos/lib/pkgconfig)

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
