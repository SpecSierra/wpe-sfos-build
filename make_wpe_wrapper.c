/* Template for WPE subprocess wrapper binary.
 * Define REAL_BINARY at compile time.
 * This ELF binary directly exec's ld-custom.so with the real subprocess.
 * Being ELF (not a shell script), it works when loaded via libpreloadpatchmanager.so
 * because our execve interceptor wraps it through ld-custom.so first. */
#define _GNU_SOURCE
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#ifndef REAL_BINARY
#error "Define REAL_BINARY"
#endif

#define LD_CUSTOM "/home/defaultuser/wpe-sfos-artifacts/lib/ld-custom.so"
#define LIB_PATH  "/home/defaultuser/wpe-sfos-artifacts/lib:/usr/lib64:/lib64"

int main(int argc, char *argv[], char *envp[]) {
    /* Build new argv for ld-custom.so: [ld-custom, --library-path, PATH, real_binary, orig_args...] */
    const char **new_argv = malloc((argc + 4) * sizeof(char *));
    if (!new_argv) return 1;
    new_argv[0] = LD_CUSTOM;
    new_argv[1] = "--library-path";
    new_argv[2] = LIB_PATH;
    new_argv[3] = REAL_BINARY;
    for (int i = 1; i < argc; i++)
        new_argv[3 + i] = argv[i];
    new_argv[3 + argc] = NULL;

    execve(LD_CUSTOM, (char *const *)new_argv, envp);
    /* If execve fails, fall back to running real binary directly */
    execv(REAL_BINARY, argv);
    perror("execve failed");
    return 127;
}
