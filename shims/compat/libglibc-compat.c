/*
 * libglibc-compat.c — shim symbols for running on Sailfish OS (glibc 2.30)
 * when binaries (e.g. libstdc++.so.6.0.33) were built against glibc 2.32-2.38.
 *
 * Compile cross-aarch64:
 *   gcc -shared -fPIC -O2 -Wl,--allow-shlib-undefined \
 *       -Wl,--version-script=libglibc-compat.map \
 *       -o libglibc-compat.so libglibc-compat.c
 */
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <errno.h>

/* glibc 2.32: global flag whether process is single-threaded.
 * libstdc++ reads this to skip locking.  0 = multi-threaded (safe). */
char __libc_single_threaded = 0;

/* glibc 2.36: cryptographic random number.
 * Use getrandom(2) syscall directly — 1 syscall vs open+read+close per call.
 * SYS_getrandom = 278 on aarch64 (asm-generic/unistd.h). */
uint32_t arc4random(void)
{
    uint32_t val = 0;
    syscall(SYS_getrandom, &val, sizeof(val), 0);
    return val;
}

/* glibc 2.36: fill buffer with random bytes.
 * getrandom() fills up to 256 bytes atomically with flags=0 (blocking).
 * Loop for larger requests. */
void arc4random_buf(void *buf, size_t nbytes)
{
    size_t done = 0;
    while (done < nbytes) {
        ssize_t n = syscall(SYS_getrandom, (char *)buf + done, nbytes - done, 0);
        if (n <= 0) break;
        done += (size_t)n;
    }
}

/* glibc 2.38: ISO C23 strtoul — semantics identical for our purposes. */
unsigned long __isoc23_strtoul(const char *nptr, char **endptr, int base)
{
    return strtoul(nptr, endptr, base);
}

unsigned long long __isoc23_strtoull(const char *nptr, char **endptr, int base)
{
    return strtoull(nptr, endptr, base);
}

long __isoc23_strtol(const char *nptr, char **endptr, int base)
{
    return strtol(nptr, endptr, base);
}

long long __isoc23_strtoll(const char *nptr, char **endptr, int base)
{
    return strtoll(nptr, endptr, base);
}

/*
 * glibc 2.33 on aarch64 added direct fstat/stat/lstat as public symbols.
 * Older glibc (2.30) on aarch64 does NOT export these as dynamic symbols —
 * they're inlined or routed through internal kernel wrappers.
 * Use direct Linux syscalls (SYS_newfstatat = 79 on aarch64) instead.
 */
#ifndef AT_EMPTY_PATH
#define AT_EMPTY_PATH 0x1000
#endif

/* NOTE: glibc's syscall(2) wrapper already returns -1 with errno set on
 * failure (it does NOT return -errno).  The previous `errno = -r` here
 * clobbered the real error with EPERM (-(-1) == 1) for EVERY failed stat,
 * so callers probing for ENOENT (sqlite, fontconfig, GIO, dlopen path
 * search) saw "permission denied" instead of "not found". */
int fstat(int fd, struct stat *buf)
{
    return (int)syscall(SYS_newfstatat, fd, "", buf, AT_EMPTY_PATH);
}

int fstat64(int fd, struct stat *buf) { return fstat(fd, buf); }

int stat(const char *path, struct stat *buf)
{
    return (int)syscall(SYS_newfstatat, AT_FDCWD, path, buf, 0);
}

int lstat(const char *path, struct stat *buf)
{
    return (int)syscall(SYS_newfstatat, AT_FDCWD, path, buf, AT_SYMLINK_NOFOLLOW);
}

/* stat64/lstat64/fstat64 — on aarch64 these are identical to the non-64 variants */
int stat64(const char *path, struct stat *buf) { return stat(path, buf); }
int lstat64(const char *path, struct stat *buf) { return lstat(path, buf); }

/*
 * glibc 2.38: strlcpy / strlcat — safe string copy/concat.
 * Not in glibc < 2.38 but widely implemented identically.
 */
size_t strlcpy(char *dst, const char *src, size_t size)
{
    size_t srclen = strlen(src);
    if (size > 0) {
        size_t copylen = srclen < size - 1 ? srclen : size - 1;
        memcpy(dst, src, copylen);
        dst[copylen] = '\0';
    }
    return srclen;
}

size_t strlcat(char *dst, const char *src, size_t size)
{
    size_t dstlen = strnlen(dst, size);
    if (dstlen == size) return size + strlen(src);
    return dstlen + strlcpy(dst + dstlen, src, size - dstlen);
}

/*
 * glibc 2.38: ISO C23 scanf variants — semantics identical to standard ones.
 */
#include <stdio.h>
#include <stdarg.h>

int __isoc23_fscanf(FILE *stream, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int r = vfscanf(stream, fmt, ap);
    va_end(ap);
    return r;
}

int __isoc23_sscanf(const char *str, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int r = vsscanf(str, fmt, ap);
    va_end(ap);
    return r;
}

int __isoc23_scanf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int r = vscanf(fmt, ap);
    va_end(ap);
    return r;
}

/*
 * glibc 2.34: dlopen/dlsym/dlerror were moved from libdl.so.2 to libc.so.6
 * and re-versioned as GLIBC_2.34.  SFOS (glibc 2.30) still has them in
 * libdl.so.2 versioned as GLIBC_2.17.  Provide GLIBC_2.34-versioned wrappers
 * that forward to the GLIBC_2.17 symbols already loaded at runtime.
 */
#include <dlfcn.h>

/* Bind the C names __compat_dl* to the GLIBC_2.17-versioned imports */
__asm__(".symver __compat_dlopen,dlopen@GLIBC_2.17");
__asm__(".symver __compat_dlsym,dlsym@GLIBC_2.17");
__asm__(".symver __compat_dlerror,dlerror@GLIBC_2.17");
extern void *__compat_dlopen(const char *pathname, int flags);
extern void *__compat_dlsym(void *handle, const char *symbol);
extern char *__compat_dlerror(void);

/* Export GLIBC_2.34-versioned wrappers */
__asm__(".symver compat_dlopen_2_34,dlopen@GLIBC_2.34");
void *compat_dlopen_2_34(const char *pathname, int flags)
    { return __compat_dlopen(pathname, flags); }

__asm__(".symver compat_dlsym_2_34,dlsym@GLIBC_2.34");
void *compat_dlsym_2_34(void *handle, const char *symbol)
    { return __compat_dlsym(handle, symbol); }

__asm__(".symver compat_dlerror_2_34,dlerror@GLIBC_2.34");
char *compat_dlerror_2_34(void)
    { return __compat_dlerror(); }

/*
 * glibc 2.35: used by static libgcc's _Unwind_Find_FDE for stack unwinding.
 * Returning -1 signals "not found"; the unwinder falls back gracefully.
 */
struct dl_find_object {
    unsigned long long dlfo_flags;
    void *dlfo_map_start;
    void *dlfo_map_end;
    void *dlfo_link_map;
    void *dlfo_eh_frame;
    void *__dlfo_reserved[7];
};

int _dl_find_object(void *addr, struct dl_find_object *result)
{
    (void)addr; (void)result;
    return -1;
}


