/* getauxval interceptor - no dlsym dependency.
 * Reads aux vector from /proc/self/auxv.
 * For standard AT types (< 50): returns real value.
 * For non-standard AT types (>= 50): returns 1 with errno=0.
 * This prevents GLib/libpreloadpatchmanager SFOS-specific booster check from crashing. */
#define _GNU_SOURCE
#include <sys/auxv.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <sys/syscall.h>

#define MAX_AT 50
static unsigned long auxv_vals[MAX_AT];
static char auxv_valid[MAX_AT];
static int auxv_loaded = 0;

static void load_auxv(void) {
    if (auxv_loaded) return;
    auxv_loaded = 1;
    int fd = open("/proc/self/auxv", O_RDONLY);
    if (fd < 0) return;
    unsigned long buf[2];
    while (read(fd, buf, 16) == 16) {
        if (buf[0] == 0) break;  /* AT_NULL */
        if (buf[0] < MAX_AT) {
            auxv_vals[buf[0]] = buf[1];
            auxv_valid[buf[0]] = 1;
        }
    }
    close(fd);
}

__attribute__((constructor))
static void init(void) {
    load_auxv();
}

unsigned long getauxval(unsigned long type) {
    load_auxv();
    if (type < MAX_AT) {
        if (auxv_valid[type]) {
            errno = 0;
            return auxv_vals[type];
        } else {
            errno = ENOENT;
            return 0;
        }
    }
    /* Non-standard AT type (SFOS booster context check) — spoof success */
    errno = 0;
    return 1;
}
