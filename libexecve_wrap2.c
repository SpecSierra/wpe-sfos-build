/* Intercept execve so ALL spawned child processes use ld-custom.so.
 * Does NOT use dlsym - uses the PLT/GOT directly to avoid libdl dependency. */
#define _GNU_SOURCE
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <sys/types.h>
#include <fcntl.h>
#include <errno.h>

#define LD_CUSTOM "/home/defaultuser/wpe-sfos-artifacts/lib/ld-custom.so"
#define LIB_PATH  "/home/defaultuser/wpe-sfos-artifacts/lib:/usr/lib64:/lib64"

/* Check if a file is an ELF binary (not a script) */
static int is_elf(const char *path) {
    if (!path) return 0;
    /* Skip ld-custom.so itself to avoid infinite loops */
    if (strstr(path, "ld-custom")) return 0;
    /* Skip shell interpreters */
    if (strstr(path, "/sh") || strstr(path, "/bash") || strstr(path, "/busybox")) return 0;
    int fd = open(path, O_RDONLY);
    if (fd < 0) return 0;
    unsigned char magic[4] = {0};
    read(fd, magic, 4);
    close(fd);
    return (magic[0] == 0x7f && magic[1] == 'E' && magic[2] == 'L' && magic[3] == 'F');
}

/* Wrap an execve call to go through ld-custom.so */
static int wrap_execve(const char *path, char *const argv[], char *const envp[]) {
    int argc = 0;
    while (argv[argc]) argc++;

    const char **new_argv = malloc((argc + 5) * sizeof(char *));
    if (!new_argv) return -1;

    new_argv[0] = LD_CUSTOM;
    new_argv[1] = "--library-path";
    new_argv[2] = LIB_PATH;
    new_argv[3] = path;
    for (int i = 1; i <= argc; i++)
        new_argv[3 + i] = argv[i];  /* includes NULL at end */

    /* Use the real syscall-level execve by bypassing our interception.
     * We call __execve (the actual libc function that's not our override). */
    int ret = execve(LD_CUSTOM, (char *const *)new_argv, envp);
    free(new_argv);
    return ret;
}

/* Override execve using the __wrap_ mechanism via -Wl,--wrap 
 * OR: simply redefine execve. This .so is loaded via LD_PRELOAD,
 * so our execve() takes precedence over libc's in the PLT. */

/* We need to call the REAL execve. Use syscall directly. */
#include <sys/syscall.h>
static int real_execve(const char *p, char *const a[], char *const e[]) {
    return (int)syscall(SYS_execve, p, a, e);
}

int execve(const char *path, char *const argv[], char *const envp[]) {
    if (!is_elf(path)) {
        return real_execve(path, argv, envp);
    }
    /* It's an ELF binary — route through ld-custom.so */
    int argc = 0;
    while (argv[argc]) argc++;

    const char **new_argv = malloc((argc + 5) * sizeof(char *));
    if (!new_argv) return real_execve(path, argv, envp);

    new_argv[0] = LD_CUSTOM;
    new_argv[1] = "--library-path";
    new_argv[2] = LIB_PATH;
    new_argv[3] = path;
    for (int i = 1; i <= argc; i++)
        new_argv[3 + i] = argv[i];

    int ret = real_execve(LD_CUSTOM, (char *const *)new_argv, envp);
    free(new_argv);
    return ret;
}
