#define _GNU_SOURCE
#include <signal.h>
#include <ucontext.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>

static int sigill_count = 0;
static int maps_dumped = 0;

static void dump_maps_for_addr(uint64_t crash_pc) {
    if (maps_dumped) return;
    maps_dumped = 1;
    
    int fd = open("/proc/self/maps", O_RDONLY);
    if (fd < 0) return;
    
    FILE *out = fopen("/tmp/wpe_maps.txt", "w");
    if (!out) { close(fd); return; }
    
    char buf[256];
    ssize_t n;
    uint64_t start, end;
    char perms[8], path[256];
    // Read maps line by line to find crash_pc
    FILE *fm = fdopen(fd, "r");
    while (fgets(buf, sizeof(buf), fm)) {
        // Parse: start-end perms offset dev inode [path]
        unsigned long long s, e;
        sscanf(buf, "%llx-%llx", &s, &e);
        if (crash_pc >= s && crash_pc < e) {
            fprintf(stderr, "[sigill_skip] CRASH in: %s", buf);
            fflush(stderr);
        }
        fputs(buf, out);
    }
    fclose(fm);
    fclose(out);
}

static void sigill_skip(int sig, siginfo_t *info, void *ctx)
{
    ucontext_t *uc = (ucontext_t *)ctx;
    sigill_count++;
    if (sigill_count == 1) {
        dump_maps_for_addr((uint64_t)uc->uc_mcontext.pc);
        fprintf(stderr, "[sigill_skip] SIGILL #%d at PC=%p\n", sigill_count, (void*)uc->uc_mcontext.pc);
        fflush(stderr);
    }
    if (sigill_count > 100) {
        fprintf(stderr, "[sigill_skip] too many SIGILLs at PC=%p, aborting\n", (void*)uc->uc_mcontext.pc);
        fflush(stderr);
        abort();
    }
    uc->uc_mcontext.pc += 4;
}

__attribute__((constructor))
static void install_handler(void)
{
    struct sigaction sa;
    sa.sa_sigaction = sigill_skip;
    sa.sa_flags     = SA_SIGINFO | SA_RESTART | SA_NODEFER;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGILL, &sa, NULL);
}
