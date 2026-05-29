/*
 * libegl-stubs.c — EGL 1.5 shim for SFOS Adreno libEGL (EGL 1.4 only)
 *
 * The Hybris/Adreno libEGL.so.1.0.0 on SFOS (Sony Xperia 10 II) does not export
 * EGL 1.5 sync / image / platform functions, but our bundled libepoxy.so.0 was
 * built against a Mesa sysroot that has them.  When libepoxy probes for
 * eglCreateSync via dlsym() and gets NULL it installs an abort() stub; any call
 * to eglCreateSync then terminates WPEWebProcess.
 *
 * This shim is deployed as wpe-sfos-artifacts/lib/libEGL.so.1.  Because
 * LD_LIBRARY_PATH=$ARTIFACTS/lib is set first, libepoxy's dlopen("libEGL.so.1")
 * finds THIS file instead of /usr/lib64/libEGL.so.1.  The NEEDED entry
 * libEGL.so.1.0.0 is satisfied by the real Adreno EGL at /usr/lib64/.
 *
 * Sync forwarding (v2 — no more no-ops):
 *   The EGL 1.5 core sync functions are forwarded to their EGL_KHR_fence_sync
 *   equivalents which the Adreno driver has supported since the 300-series.
 *   Returning EGL_NO_SYNC from eglCreateSync caused WebKit to fall back to
 *   glFinish() — a full GPU stall on every frame — destroying CPU/GPU
 *   parallelism.  Forwarding to real fence objects restores async sync.
 *
 * Fallback policy (KHR not available):
 *   eglCreateSync       → EGL_NO_SYNC  (WebKit falls back to CPU-side sync)
 *   eglDestroySync      → EGL_TRUE     (no-op)
 *   eglClientWaitSync   → EGL_CONDITION_SATISFIED (pretend ready)
 *   eglWaitSync         → EGL_TRUE
 *   eglGetSyncAttrib    → EGL_FALSE
 *
 * Image / platform (unchanged):
 *   eglCreateImage      → forward to eglCreateImageKHR via eglGetProcAddress
 *   eglDestroyImage     → forward to eglDestroyImageKHR via eglGetProcAddress
 *   eglCreatePlatformDisplay        → EGL_NO_DISPLAY
 *   eglCreatePlatformWindowSurface  → EGL_NO_SURFACE
 */

#include <dlfcn.h>
#include <stdint.h>

/* Minimal EGL type definitions to avoid pulling in full EGL headers */
typedef void   *EGLDisplay;
typedef void   *EGLSync;
typedef void   *EGLImage;
typedef void   *EGLContext;
typedef void   *EGLSurface;
typedef void   *EGLConfig;
typedef void   *EGLClientBuffer;
typedef unsigned int  EGLenum;
typedef int           EGLint;
typedef int           EGLBoolean;
typedef intptr_t      EGLAttrib;
typedef uint64_t      EGLTimeKHR;

/* EGLSyncKHR is the same underlying type as EGLSync (void*) */
typedef void   *EGLSyncKHR;

#define EGL_NO_SYNC       ((EGLSync)0)
#define EGL_NO_IMAGE      ((EGLImage)0)
#define EGL_NO_DISPLAY    ((EGLDisplay)0)
#define EGL_NO_SURFACE    ((EGLSurface)0)
#define EGL_NONE          0x3038
#define EGL_FALSE         0
#define EGL_TRUE          1
#define EGL_CONDITION_SATISFIED 0x30F6

/* eglGetProcAddress is in the real libEGL via NEEDED; resolved at runtime */
extern void *eglGetProcAddress(const char *name);

/* ---- KHR function pointer types ---------------------------------- */

typedef EGLSyncKHR (*eglCreateSyncKHR_t)(EGLDisplay, EGLenum, const EGLint *);
typedef EGLBoolean (*eglDestroySyncKHR_t)(EGLDisplay, EGLSyncKHR);
typedef EGLint     (*eglClientWaitSyncKHR_t)(EGLDisplay, EGLSyncKHR, EGLint, EGLTimeKHR);
typedef EGLBoolean (*eglWaitSyncKHR_t)(EGLDisplay, EGLSyncKHR, EGLint);
typedef EGLBoolean (*eglGetSyncAttribKHR_t)(EGLDisplay, EGLSyncKHR, EGLint, EGLint *);

/* Lazy-resolved once; (void*)-1 means "not yet probed" */
static eglCreateSyncKHR_t      fn_createSync      = (eglCreateSyncKHR_t)-1;
static eglDestroySyncKHR_t     fn_destroySync     = (eglDestroySyncKHR_t)-1;
static eglClientWaitSyncKHR_t  fn_clientWaitSync  = (eglClientWaitSyncKHR_t)-1;
static eglWaitSyncKHR_t        fn_waitSync        = (eglWaitSyncKHR_t)-1;
static eglGetSyncAttribKHR_t   fn_getSyncAttrib   = (eglGetSyncAttribKHR_t)-1;

/* Helper: convert EGLAttrib (intptr_t) list → EGLint list (in-place, 64-entry max) */
static void attrib_to_int(const EGLAttrib *src, EGLint *dst, int max)
{
    int i = 0;
    if (src) {
        while (src[i] != EGL_NONE && i < max - 1) {
            dst[i] = (EGLint)src[i];
            i++;
        }
    }
    dst[i] = EGL_NONE;
}

/* ---- EGL 1.5 sync — forward to EGL_KHR_fence_sync ---------------- */

EGLSync eglCreateSync(EGLDisplay dpy, EGLenum type, const EGLAttrib *attrib_list)
{
    if (fn_createSync == (eglCreateSyncKHR_t)-1)
        fn_createSync = (eglCreateSyncKHR_t)eglGetProcAddress("eglCreateSyncKHR");
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
        fn_destroySync = (eglDestroySyncKHR_t)eglGetProcAddress("eglDestroySyncKHR");
    if (fn_destroySync && sync != EGL_NO_SYNC)
        return fn_destroySync(dpy, (EGLSyncKHR)sync);
    return EGL_TRUE;
}

EGLint eglClientWaitSync(EGLDisplay dpy, EGLSync sync, EGLint flags, EGLTimeKHR timeout)
{
    if (fn_clientWaitSync == (eglClientWaitSyncKHR_t)-1)
        fn_clientWaitSync = (eglClientWaitSyncKHR_t)eglGetProcAddress("eglClientWaitSyncKHR");
    if (fn_clientWaitSync && sync != EGL_NO_SYNC)
        return fn_clientWaitSync(dpy, (EGLSyncKHR)sync, flags, timeout);
    return EGL_CONDITION_SATISFIED;
}

EGLBoolean eglWaitSync(EGLDisplay dpy, EGLSync sync, EGLint flags)
{
    if (fn_waitSync == (eglWaitSyncKHR_t)-1)
        fn_waitSync = (eglWaitSyncKHR_t)eglGetProcAddress("eglWaitSyncKHR");
    if (fn_waitSync && sync != EGL_NO_SYNC)
        return fn_waitSync(dpy, (EGLSyncKHR)sync, flags);
    return EGL_TRUE;
}

EGLBoolean eglGetSyncAttrib(EGLDisplay dpy, EGLSync sync, EGLAttrib attribute, EGLAttrib *value)
{
    if (fn_getSyncAttrib == (eglGetSyncAttribKHR_t)-1)
        fn_getSyncAttrib = (eglGetSyncAttribKHR_t)eglGetProcAddress("eglGetSyncAttribKHR");
    if (fn_getSyncAttrib && sync != EGL_NO_SYNC) {
        EGLint int_val = 0;
        EGLBoolean result = fn_getSyncAttrib(dpy, (EGLSyncKHR)sync, (EGLint)attribute, &int_val);
        if (result && value)
            *value = (EGLAttrib)int_val;
        return result;
    }
    return EGL_FALSE;
}

/* ---- EGL 1.5 image (forward to KHR extension) -------------------- */

typedef EGLImage (*eglCreateImageKHR_t)(EGLDisplay, EGLContext, EGLenum,
                                        EGLClientBuffer, const EGLint *);
typedef EGLBoolean (*eglDestroyImageKHR_t)(EGLDisplay, EGLImage);

/* eglGetProcAddress is in the real libEGL via NEEDED; resolved at runtime */
extern void *eglGetProcAddress(const char *name);

EGLImage eglCreateImage(EGLDisplay dpy, EGLContext ctx, EGLenum target,
                        EGLClientBuffer buf, const EGLAttrib *attrib_list)
{
    static eglCreateImageKHR_t fn = (void *)-1;
    if (fn == (void *)-1)
        fn = (eglCreateImageKHR_t)eglGetProcAddress("eglCreateImageKHR");
    if (!fn)
        return EGL_NO_IMAGE;

    /* Convert EGLAttrib (intptr_t) list to EGLint list */
    EGLint int_list[64];
    int i = 0;
    if (attrib_list) {
        while (attrib_list[i] != 0x3038 /* EGL_NONE */ && i < 62) {
            int_list[i] = (EGLint)attrib_list[i];
            i++;
        }
    }
    int_list[i] = 0x3038; /* EGL_NONE */

    return fn(dpy, ctx, target, buf, int_list);
}

EGLBoolean eglDestroyImage(EGLDisplay dpy, EGLImage image)
{
    static eglDestroyImageKHR_t fn = (void *)-1;
    if (fn == (void *)-1)
        fn = (eglDestroyImageKHR_t)eglGetProcAddress("eglDestroyImageKHR");
    if (!fn)
        return EGL_FALSE;
    return fn(dpy, image);
}

/* ---- EGL 1.5 platform stubs (not needed for basic rendering) ------ */

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
