# Native cmake toolchain for WPEWebKit on aarch64 Ubuntu
# Targets ARMv8.0-A (Snapdragon 665 / SFOS) but uses host Ubuntu libs.
# SFOS sysroot is NOT used here — glibc version tags are patched post-link.
set(CMAKE_SYSTEM_NAME  Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_STAGING_PREFIX /opt/wpe-sfos)

set(CMAKE_C_FLAGS   "${CMAKE_C_FLAGS}   -march=armv8-a -mtune=cortex-a73.cortex-a53 -mno-outline-atomics -fno-semantic-interposition -I/usr/include/gio-unix-2.0")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=armv8-a -mtune=cortex-a73.cortex-a53 -mno-outline-atomics -fno-semantic-interposition -I/usr/include/gio-unix-2.0")

# ── GCC Thin/Parallel LTO ─────────────────────────────────────────────────────
# GCC does not support -flto=thin (that is Clang-only).  The GCC equivalent is
# -flto=auto, which partitions LTRANS units across all available CPUs during the
# link phase.  On this 16-core build host the link phase runs after Ninja's
# parallel compile phase, so -flto=auto will fully utilise the box without
# competing with per-TU compilation jobs.
#
# cmake_ar/nm/ranlib must be the gcc-wrapper variants so that static archive
# members carry GCC GIMPLE IR that the link-time LTO pass can see.
set(CMAKE_C_FLAGS   "${CMAKE_C_FLAGS}   -flto=auto")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -flto=auto")
set(CMAKE_EXE_LINKER_FLAGS    "${CMAKE_EXE_LINKER_FLAGS}    -flto=auto -fuse-ld=gold")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -flto=auto -fuse-ld=gold")
set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} -flto=auto -fuse-ld=gold")
set(CMAKE_AR     "gcc-ar")
set(CMAKE_NM     "gcc-nm")
set(CMAKE_RANLIB "gcc-ranlib")

set(STATIC_RUNTIME_FLAGS "-static-libstdc++ -static-libgcc -Wl,--allow-shlib-undefined -Wl,-rpath-link=/opt/sfos-sysroot/usr/lib64")
set(CMAKE_EXE_LINKER_FLAGS_INIT    "${STATIC_RUNTIME_FLAGS}")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${STATIC_RUNTIME_FLAGS}")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "${STATIC_RUNTIME_FLAGS}")
set(CMAKE_EXE_LINKER_FLAGS    "${CMAKE_EXE_LINKER_FLAGS}    ${STATIC_RUNTIME_FLAGS}")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${STATIC_RUNTIME_FLAGS}")
set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} ${STATIC_RUNTIME_FLAGS}")

add_compile_definitions(U_DISABLE_RENAMING=1)
