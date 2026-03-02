/*
 * libsigill_skip.so — installed via LD_PRELOAD before libpreloadpatchmanager.so
 * runs its init.  On aarch64, __builtin_trap() emits a 4-byte "brk"/"udf"
 * instruction.  We install a SIGILL handler that simply advances PC by 4
 * so execution continues past the trap.  After libpreloadpatchmanager's init
 * finishes we restore the default handler.
 *
 * Init-function ordering in glibc: libraries loaded later have their
 * constructors called FIRST — so our constructor (LD_PRELOAD, loaded after
 * /etc/ld.so.preload) runs before libpreloadpatchmanager's constructor.
 */
#define _GNU_SOURCE
#include <signal.h>
#include <ucontext.h>
#include <stdint.h>

static struct sigaction old_sa;

static void sigill_skip(int sig, siginfo_t *info, void *ctx)
{
    ucontext_t *uc = (ucontext_t *)ctx;
    /* Skip the 4-byte illegal instruction and resume */
    uc->uc_mcontext.pc += 4;
    /* Restore default handler so we don't suppress real ILLs later */
    sigaction(SIGILL, &old_sa, NULL);
}

__attribute__((constructor))
static void install_handler(void)
{
    struct sigaction sa;
    sa.sa_sigaction = sigill_skip;
    sa.sa_flags     = SA_SIGINFO | SA_RESTART;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGILL, &sa, &old_sa);
}
