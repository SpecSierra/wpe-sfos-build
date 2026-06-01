# Clang/lld toolchain for WPEWebKit on aarch64 Ubuntu (native build).
#
# Switching from GCC to Clang enables ThinLTO: WebKit's own
# WebKitCompilerFlags.cmake guards LTO under COMPILER_IS_CLANG because GCC
# LTO dead-strips JSC's LLInt/IPInt symbols that are called only from
# hand-assembled stubs (invisible to GIMPLE IR).  With Clang + LLVM IR,
# those call edges are preserved through the ThinLTO pipeline.
#
# ThinLTO gives ~10–18% Speedometer improvement over no-LTO via cross-module
# inlining of:
#   - JSC inline cache fast paths (StructureStubInfo → JIT-emitted stubs)
#   - GC write barrier hot path (Heap::writeBarrier inline chain)
#   - B3/FTL code-generator helpers called millions of times per page load
#
# lld is required: GNU ld does not understand LLVM bitcode sections.

set(CMAKE_SYSTEM_NAME  Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_STAGING_PREFIX /opt/wpe-sfos)

set(CMAKE_C_COMPILER   clang-18)
set(CMAKE_CXX_COMPILER clang++-18)

# ── Architecture ─────────────────────────────────────────────────────────────
# Same target ISA as the GCC toolchain: ARMv8.0-A for Snapdragon 665.
# +simd+crypto: NEON vector ops + hardware AES/SHA2.
# -mno-outline-atomics: keep inline LL/SC atomics; Kryo 260 does not need the
#   out-of-line LSE atomic fallback dispatcher.
# -fno-semantic-interposition: devirtualise intra-DSO calls (same as GCC path).
set(CMAKE_C_FLAGS   "${CMAKE_C_FLAGS}   -march=armv8-a+simd+crypto -mtune=cortex-a73.cortex-a53 -mno-outline-atomics -fno-semantic-interposition -I/usr/include/gio-unix-2.0")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=armv8-a+simd+crypto -mtune=cortex-a73.cortex-a53 -mno-outline-atomics -fno-semantic-interposition -I/usr/include/gio-unix-2.0")

# ── Linker ───────────────────────────────────────────────────────────────────
# lld is mandatory for ThinLTO (LLVM bitcode sections).
# -Wl,-O2: lld string-table and section merging at the highest safe level.
# --allow-shlib-undefined: sysroot is incomplete (SFOS system libs not on
#   the build host); references are resolved at device runtime.
set(CMAKE_EXE_LINKER_FLAGS_INIT    "-fuse-ld=lld -rtlib=compiler-rt -static-libstdc++ -Wl,--allow-shlib-undefined -Wl,-rpath-link=/opt/sfos-sysroot/usr/lib64 -Wl,-O2")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-fuse-ld=lld -rtlib=compiler-rt -static-libstdc++ -Wl,--allow-shlib-undefined -Wl,-rpath-link=/opt/sfos-sysroot/usr/lib64 -Wl,-O2")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "-fuse-ld=lld -rtlib=compiler-rt -static-libstdc++ -Wl,--allow-shlib-undefined -Wl,-rpath-link=/opt/sfos-sysroot/usr/lib64 -Wl,-O2")
set(CMAKE_EXE_LINKER_FLAGS         "${CMAKE_EXE_LINKER_FLAGS}    ${CMAKE_EXE_LINKER_FLAGS_INIT}")
set(CMAKE_SHARED_LINKER_FLAGS      "${CMAKE_SHARED_LINKER_FLAGS} ${CMAKE_SHARED_LINKER_FLAGS_INIT}")
set(CMAKE_MODULE_LINKER_FLAGS      "${CMAKE_MODULE_LINKER_FLAGS} ${CMAKE_MODULE_LINKER_FLAGS_INIT}")

# ── LTO-aware archiver ───────────────────────────────────────────────────────
# Required so that static libs contain LLVM bitcode objects that ThinLTO can
# inline across.  Without these, cmake falls back to system ar/nm/ranlib which
# cannot handle bitcode and silently disables cross-module optimisation.
set(CMAKE_AR     "llvm-ar-18")
set(CMAKE_NM     "llvm-nm-18")
set(CMAKE_RANLIB "llvm-ranlib-18")

add_compile_definitions(U_DISABLE_RENAMING=1)
