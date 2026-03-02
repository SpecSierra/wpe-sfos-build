/* Intercept getauxval to prevent GLib's "getauxval () failed" fatal error.
 * GLib 2.76+ calls getauxval(AT_HWCAP) and crashes if errno is set.
 * On SFOS via ld-custom.so, something causes errno=ENOENT.
 * We wrap getauxval to clear errno and return 0 when the real call fails. */
#define _GNU_SOURCE
#include <sys/auxv.h>
#include <errno.h>
#include <dlfcn.h>

/* Use the real getauxval from libc */
static unsigned long (*real_getauxval)(unsigned long) = 0;

unsigned long getauxval(unsigned long type) {
    if (!real_getauxval)
        real_getauxval = dlsym(RTLD_NEXT, "getauxval");
    int saved = errno;
    unsigned long val = real_getauxval ? real_getauxval(type) : 0;
    if (errno == ENOENT) {
        errno = 0;  /* Clear the error — GLib checks errno after getauxval */
    }
    return val;
}
