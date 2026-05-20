#define _GNU_SOURCE
#include <signal.h>
#include <ucontext.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static int sigill_count = 0;

static void sigill_skip(int sig, siginfo_t *info, void *ctx)
{
    ucontext_t *uc = (ucontext_t *)ctx;
    sigill_count++;
    fprintf(stderr, "[sigill_skip] SIGILL #%d at PC=%p, advancing +4\n",
            sigill_count, (void*)uc->uc_mcontext.pc);
    fflush(stderr);
    if (sigill_count > 50) {
        fprintf(stderr, "[sigill_skip] too many SIGILLs, giving up\n");
        abort();
    }
    uc->uc_mcontext.pc += 4;
    /* Keep handler installed (don't restore default) */
}

__attribute__((constructor))
static void install_handler(void)
{
    struct sigaction sa;
    sa.sa_sigaction = sigill_skip;
    sa.sa_flags     = SA_SIGINFO | SA_RESTART | SA_NODEFER;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGILL, &sa, NULL);
    fprintf(stderr, "[sigill_skip] SIGILL handler installed\n");
    fflush(stderr);
}
