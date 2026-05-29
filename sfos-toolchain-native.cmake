# Native cmake toolchain for WPEWebKit on aarch64 Ubuntu
# Targets ARMv8.0-A (Snapdragon 665 / SFOS) but uses host Ubuntu libs.
# SFOS sysroot is NOT used here — glibc version tags are patched post-link.
set(CMAKE_SYSTEM_NAME  Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_STAGING_PREFIX /opt/wpe-sfos)

set(CMAKE_C_FLAGS   "${CMAKE_C_FLAGS}   -march=armv8-a -mtune=cortex-a73.cortex-a53 -mno-outline-atomics -fno-semantic-interposition -I/usr/include/gio-unix-2.0")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=armv8-a -mtune=cortex-a73.cortex-a53 -mno-outline-atomics -fno-semantic-interposition -I/usr/include/gio-unix-2.0")

# ── LTO note ─────────────────────────────────────────────────────────────────
# GCC -flto=auto is NOT used here.  WebKit's JSC LLInt/IPInt (offline assembler
# → .S files) defines symbols such as slow_path_wasm_unwind_exception and
# ipint_extern_unreachable_breakpoint_handler that are called only from assembly
# stubs — invisible to GCC's GIMPLE IR graph.  GCC LTO dead-strips those C++
# functions because it sees no IR callers, breaking the final link.
# WebKit's own cmake only enables LTO for Clang (COMPILER_IS_CLANG guard in
# WebKitCompilerFlags.cmake).  gcc-ar/nm/ranlib are kept as LTO-aware tools
# in case a future change re-enables LTO for a subset of targets.
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
