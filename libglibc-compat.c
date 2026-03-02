/*
 * libglibc-compat.c — shim symbols for running on Sailfish OS (glibc 2.30)
 * when binaries (e.g. libstdc++.so.6.0.33) were built against glibc 2.32-2.38.
 *
 * Compile cross-aarch64:
 *   aarch64-linux-gnu-gcc -shared -fPIC -O2 -nostartfiles \
 *       --sysroot=/opt/sfos-sysroot \
 *       -o libglibc-compat.so libglibc-compat.c
 */
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/stat.h>

/* glibc 2.32: global flag whether process is single-threaded.
 * libstdc++ reads this to skip locking.  0 = multi-threaded (safe). */
char __libc_single_threaded = 0;

/* glibc 2.36: cryptographic random number.  Fall back to /dev/urandom. */
uint32_t arc4random(void)
{
    uint32_t val = 0;
    int fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
    if (fd >= 0) {
        (void)read(fd, &val, sizeof(val));
        close(fd);
    }
    return val;
}

/* glibc 2.36: fill buffer with random bytes. */
void arc4random_buf(void *buf, size_t nbytes)
{
    int fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
    if (fd >= 0) {
        size_t done = 0;
        while (done < nbytes) {
            ssize_t n = read(fd, (char *)buf + done, nbytes - done);
            if (n <= 0) break;
            done += (size_t)n;
        }
        close(fd);
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
 * Older glibc (2.30) on aarch64 routes these through __fxstat/__xstat/__lxstat
 * internally; they are NOT exported as dynamic symbols.
 * We implement fstat/stat/lstat using fstatat / the *at syscall wrappers
 * which ARE available in glibc 2.30.
 */
int fstat(int fd, struct stat *buf)
{
    return fstatat(fd, "", buf, 0x1000 /* AT_EMPTY_PATH */);
}

int stat(const char *path, struct stat *buf)
{
    return fstatat(AT_FDCWD, path, buf, 0);
}

int lstat(const char *path, struct stat *buf)
{
    return fstatat(AT_FDCWD, path, buf, AT_SYMLINK_NOFOLLOW);
}

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
