# Native cmake toolchain for WPEWebKit on aarch64 Ubuntu
# Targets ARMv8.0-A (Snapdragon 665 / SFOS) but uses host Ubuntu libs.
# SFOS sysroot is NOT used here — glibc version tags are patched post-link.
set(CMAKE_SYSTEM_NAME  Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_STAGING_PREFIX /opt/wpe-sfos)

set(CMAKE_C_FLAGS   "${CMAKE_C_FLAGS}   -march=armv8-a -mno-outline-atomics")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=armv8-a -mno-outline-atomics")

set(STATIC_RUNTIME_FLAGS "-static-libstdc++ -static-libgcc -Wl,--allow-shlib-undefined -Wl,-rpath-link=/opt/sfos-sysroot/usr/lib64")
set(CMAKE_EXE_LINKER_FLAGS_INIT    "${STATIC_RUNTIME_FLAGS}")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${STATIC_RUNTIME_FLAGS}")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "${STATIC_RUNTIME_FLAGS}")
set(CMAKE_EXE_LINKER_FLAGS    "${CMAKE_EXE_LINKER_FLAGS}    ${STATIC_RUNTIME_FLAGS}")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${STATIC_RUNTIME_FLAGS}")
set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} ${STATIC_RUNTIME_FLAGS}")

add_compile_definitions(U_DISABLE_RENAMING=1)
