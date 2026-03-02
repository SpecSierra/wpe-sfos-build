/* Intercept execve/execvpe so ALL spawned child processes use ld-custom.so.
 * This bypasses /etc/ld.so.preload (which loads libpreloadpatchmanager.so)
 * for every process spawned from MiniBrowser and its subprocesses. */
#define _GNU_SOURCE
#include <unistd.h>
#include <dlfcn.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>

#define LD_CUSTOM "/home/defaultuser/wpe-sfos-artifacts/lib/ld-custom.so"
#define LIB_PATH  "/home/defaultuser/wpe-sfos-artifacts/lib:/usr/lib64:/lib64"

/* Skip wrapping the dynamic linker itself and shell scripts */
static int should_wrap(const char *path) {
    if (!path) return 0;
    /* Don't wrap ld-custom.so (would infinite loop) */
    if (strstr(path, "ld-custom")) return 0;
    /* Don't wrap shell/script interpreters — they exec themselves anyway */
    if (strstr(path, "/sh") || strstr(path, "/bash") || strstr(path, "/busybox")) return 0;
    /* Only wrap ELF binaries (check magic bytes) */
    FILE *f = fopen(path, "rb");
    if (!f) return 0;
    unsigned char magic[4];
    int n = fread(magic, 1, 4, f);
    fclose(f);
    if (n < 4) return 0;
    return (magic[0] == 0x7f && magic[1] == 'E' && magic[2] == 'L' && magic[3] == 'F');
}

static int (*real_execve)(const char *, char *const[], char *const[]) = NULL;

int execve(const char *path, char *const argv[], char *const envp[]) {
    if (!real_execve)
        real_execve = dlsym(RTLD_NEXT, "execve");

    if (!should_wrap(path))
        return real_execve(path, argv, envp);

    /* Count argv */
    int argc = 0;
    while (argv[argc]) argc++;

    /* Build new argv: [ld-custom.so, --library-path, LIB_PATH, path, argv[1]...] */
    const char **new_argv = malloc((argc + 4) * sizeof(char *));
    if (!new_argv) return real_execve(path, argv, envp);

    new_argv[0] = LD_CUSTOM;
    new_argv[1] = "--library-path";
    new_argv[2] = LIB_PATH;
    new_argv[3] = path;
    for (int i = 1; i <= argc; i++)
        new_argv[3 + i] = argv[i];  /* argv[argc] is NULL, copies that too */

    int ret = real_execve(LD_CUSTOM, (char *const *)new_argv, envp);
    free(new_argv);
    return ret;
}

/* Also intercept posix_spawn if used */
#include <spawn.h>
static int (*real_posix_spawn)(pid_t*, const char*, const posix_spawn_file_actions_t*,
    const posix_spawnattr_t*, char *const[], char *const[]) = NULL;

int posix_spawn(pid_t *pid, const char *path,
    const posix_spawn_file_actions_t *fa, const posix_spawnattr_t *attr,
    char *const argv[], char *const envp[]) {
    if (!real_posix_spawn)
        real_posix_spawn = dlsym(RTLD_NEXT, "posix_spawn");
    if (!should_wrap(path))
        return real_posix_spawn(pid, path, fa, attr, argv, envp);

    int argc = 0;
    while (argv[argc]) argc++;
    const char **new_argv = malloc((argc + 4) * sizeof(char *));
    if (!new_argv) return real_posix_spawn(pid, path, fa, attr, argv, envp);

    new_argv[0] = LD_CUSTOM;
    new_argv[1] = "--library-path";
    new_argv[2] = LIB_PATH;
    new_argv[3] = path;
    for (int i = 1; i <= argc; i++)
        new_argv[3 + i] = argv[i];

    int ret = real_posix_spawn(pid, LD_CUSTOM, fa, attr, (char *const *)new_argv, envp);
    free(new_argv);
    return ret;
}
