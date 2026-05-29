/*
 * libegl-stubs.c — EGL 1.5 shim for SFOS Adreno libEGL (EGL 1.4 only)
 *
 * The Hybris/Adreno libEGL.so.1.0.0 on SFOS (Sony Xperia 10 II) does not export
 * EGL 1.5 sync / image / platform functions, but our bundled libepoxy.so.0 was
 * built against a Mesa sysroot that has them.  When libepoxy probes for
 * eglCreateSync via dlsym() and gets NULL it installs an abort() stub; any call
 * to eglCreateSync then terminates WPEWebProcess.
 *
 * This shim is deployed via LD_PRELOAD so the real libEGL.so.1 is NOT yet
 * loaded when this shim is mapped.  We must NOT use an extern declaration for
 * eglGetProcAddress — the linker will fail with "undefined symbol" at first
 * call because the real libEGL hasn't been opened yet.  Instead we resolve it
 * lazily via dlsym(RTLD_DEFAULT, ...) once the real EGL is loaded by libepoxy.
 *
 * Sync policy (EGL 1.5 → EGL_KHR_fence_sync forwarding):
 *   eglCreateSync       → eglCreateSyncKHR    (real fence, avoids glFinish())
 *   eglDestroySync      → eglDestroySyncKHR
 *   eglClientWaitSync   → eglClientWaitSyncKHR
 *   eglWaitSync         → eglWaitSyncKHR
 *   eglGetSyncAttrib    → eglGetSyncAttribKHR
 *   Fallback (KHR unavailable): original no-op behaviour.
 *
 * Image policy:
 *   eglCreateImage      → eglCreateImageKHR   (via runtime dlsym)
 *   eglDestroyImage     → eglDestroyImageKHR  (via runtime dlsym)
 *
 * Platform stubs (not needed for basic rendering):
 *   eglCreatePlatformDisplay        → EGL_NO_DISPLAY
 *   eglCreatePlatformWindowSurface  → EGL_NO_SURFACE
 */

#include <dlfcn.h>
#include <stdint.h>

/* Minimal EGL type definitions */
typedef void         *EGLDisplay;
typedef void         *EGLSync;
typedef void         *EGLSyncKHR;
typedef void         *EGLImage;
typedef void         *EGLContext;
typedef void         *EGLSurface;
typedef void         *EGLConfig;
typedef void         *EGLClientBuffer;
typedef unsigned int  EGLenum;
typedef int           EGLint;
typedef int           EGLBoolean;
typedef intptr_t      EGLAttrib;
typedef uint64_t      EGLTimeKHR;

#define EGL_NO_SYNC             ((EGLSync)0)
#define EGL_NO_IMAGE            ((EGLImage)0)
#define EGL_NO_DISPLAY          ((EGLDisplay)0)
#define EGL_NO_SURFACE          ((EGLSurface)0)
#define EGL_NONE                0x3038
#define EGL_FALSE               0
#define EGL_TRUE                1
#define EGL_CONDITION_SATISFIED 0x30F6

/* ---- Runtime eglGetProcAddress resolution ------------------------- */
/*
 * Cannot use `extern eglGetProcAddress` — this shim has no NEEDED entry for
 * libEGL.so.1, so the PLT slot is never filled and the first call crashes with
 * "undefined symbol".  Instead: resolve at runtime after libepoxy has opened
 * the real libEGL.
 */
typedef void *(*eglGetProcAddress_t)(const char *);

static eglGetProcAddress_t get_egl_get_proc_address(void)
{
    static eglGetProcAddress_t fn = NULL;
    if (!fn)
        fn = (eglGetProcAddress_t)dlsym(RTLD_DEFAULT, "eglGetProcAddress");
    return fn;
}

static void *egl_get_proc(const char *name)
{
    eglGetProcAddress_t fn = get_egl_get_proc_address();
    return fn ? fn(name) : NULL;
}

/* ---- KHR function pointer types ---------------------------------- */
typedef EGLSyncKHR (*eglCreateSyncKHR_t)(EGLDisplay, EGLenum, const EGLint *);
typedef EGLBoolean (*eglDestroySyncKHR_t)(EGLDisplay, EGLSyncKHR);
typedef EGLint     (*eglClientWaitSyncKHR_t)(EGLDisplay, EGLSyncKHR, EGLint, EGLTimeKHR);
typedef EGLBoolean (*eglWaitSyncKHR_t)(EGLDisplay, EGLSyncKHR, EGLint);
typedef EGLBoolean (*eglGetSyncAttribKHR_t)(EGLDisplay, EGLSyncKHR, EGLint, EGLint *);

/* NULL-1 sentinel = "not yet probed"; NULL = "probed, not available" */
static eglCreateSyncKHR_t     fn_createSync     = (eglCreateSyncKHR_t)-1;
static eglDestroySyncKHR_t    fn_destroySync    = (eglDestroySyncKHR_t)-1;
static eglClientWaitSyncKHR_t fn_clientWaitSync = (eglClientWaitSyncKHR_t)-1;
static eglWaitSyncKHR_t       fn_waitSync       = (eglWaitSyncKHR_t)-1;
static eglGetSyncAttribKHR_t  fn_getSyncAttrib  = (eglGetSyncAttribKHR_t)-1;

/* Convert EGLAttrib (intptr_t) list to EGLint list; max 64 entries */
static void attrib_to_int(const EGLAttrib *src, EGLint *dst, int max)
{
    int i = 0;
    if (src) {
        while (i < max - 1 && src[i] != EGL_NONE) {
            dst[i] = (EGLint)src[i];
            i++;
        }
    }
    dst[i] = EGL_NONE;
}

/* ---- EGL 1.5 sync → EGL_KHR_fence_sync --------------------------- */

EGLSync eglCreateSync(EGLDisplay dpy, EGLenum type, const EGLAttrib *attrib_list)
{
    if (fn_createSync == (eglCreateSyncKHR_t)-1)
        fn_createSync = (eglCreateSyncKHR_t)egl_get_proc("eglCreateSyncKHR");
    if (fn_createSync) {
        EGLint int_attrs[64];
        attrib_to_int(attrib_list, int_attrs, 64);
        return (EGLSync)fn_createSync(dpy, type, int_attrs);
    }
    return EGL_NO_SYNC;
}

EGLBoolean eglDestroySync(EGLDisplay dpy, EGLSync sync)
{
    if (fn_destroySync == (eglDestroySyncKHR_t)-1)
        fn_destroySync = (eglDestroySyncKHR_t)egl_get_proc("eglDestroySyncKHR");
    if (fn_destroySync && sync)
        return fn_destroySync(dpy, (EGLSyncKHR)sync);
    return EGL_TRUE;
}

EGLint eglClientWaitSync(EGLDisplay dpy, EGLSync sync, EGLint flags, EGLTimeKHR timeout)
{
    if (fn_clientWaitSync == (eglClientWaitSyncKHR_t)-1)
        fn_clientWaitSync = (eglClientWaitSyncKHR_t)egl_get_proc("eglClientWaitSyncKHR");
    if (fn_clientWaitSync && sync)
        return fn_clientWaitSync(dpy, (EGLSyncKHR)sync, flags, timeout);
    return EGL_CONDITION_SATISFIED;
}

EGLBoolean eglWaitSync(EGLDisplay dpy, EGLSync sync, EGLint flags)
{
    if (fn_waitSync == (eglWaitSyncKHR_t)-1)
        fn_waitSync = (eglWaitSyncKHR_t)egl_get_proc("eglWaitSyncKHR");
    if (fn_waitSync && sync)
        return fn_waitSync(dpy, (EGLSyncKHR)sync, flags);
    return EGL_TRUE;
}

EGLBoolean eglGetSyncAttrib(EGLDisplay dpy, EGLSync sync, EGLAttrib attribute, EGLAttrib *value)
{
    if (fn_getSyncAttrib == (eglGetSyncAttribKHR_t)-1)
        fn_getSyncAttrib = (eglGetSyncAttribKHR_t)egl_get_proc("eglGetSyncAttribKHR");
    if (fn_getSyncAttrib && sync) {
        EGLint int_val = 0;
        EGLBoolean result = fn_getSyncAttrib(dpy, (EGLSyncKHR)sync, (EGLint)attribute, &int_val);
        if (result && value)
            *value = (EGLAttrib)int_val;
        return result;
    }
    return EGL_FALSE;
}

/* ---- EGL 1.5 image → KHR extension ------------------------------- */

typedef EGLImage   (*eglCreateImageKHR_t)(EGLDisplay, EGLContext, EGLenum,
                                          EGLClientBuffer, const EGLint *);
typedef EGLBoolean (*eglDestroyImageKHR_t)(EGLDisplay, EGLImage);

EGLImage eglCreateImage(EGLDisplay dpy, EGLContext ctx, EGLenum target,
                        EGLClientBuffer buf, const EGLAttrib *attrib_list)
{
    static eglCreateImageKHR_t fn = (eglCreateImageKHR_t)-1;
    if (fn == (eglCreateImageKHR_t)-1)
        fn = (eglCreateImageKHR_t)egl_get_proc("eglCreateImageKHR");
    if (!fn)
        return EGL_NO_IMAGE;
    EGLint int_list[64];
    attrib_to_int(attrib_list, int_list, 64);
    return fn(dpy, ctx, target, buf, int_list);
}

EGLBoolean eglDestroyImage(EGLDisplay dpy, EGLImage image)
{
    static eglDestroyImageKHR_t fn = (eglDestroyImageKHR_t)-1;
    if (fn == (eglDestroyImageKHR_t)-1)
        fn = (eglDestroyImageKHR_t)egl_get_proc("eglDestroyImageKHR");
    if (!fn)
        return EGL_FALSE;
    return fn(dpy, image);
}

/* ---- EGL 1.5 platform stubs -------------------------------------- */

EGLDisplay eglCreatePlatformDisplay(EGLenum platform, void *native_display,
                                    const EGLAttrib *attrib_list)
{
    (void)platform; (void)native_display; (void)attrib_list;
    return EGL_NO_DISPLAY;
}

EGLSurface eglCreatePlatformWindowSurface(EGLDisplay dpy, EGLConfig config,
                                          void *native_window,
                                          const EGLAttrib *attrib_list)
{
    (void)dpy; (void)config; (void)native_window; (void)attrib_list;
    return EGL_NO_SURFACE;
}
