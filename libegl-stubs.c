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
 * Stub policy:
 *   eglCreateSync       → EGL_NO_SYNC  (WebKit falls back to CPU-side sync)
 *   eglDestroySync      → EGL_TRUE     (no-op)
 *   eglClientWaitSync   → EGL_CONDITION_SATISFIED (pretend ready)
 *   eglWaitSync         → EGL_TRUE
 *   eglGetSyncAttrib    → EGL_FALSE
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

#define EGL_NO_SYNC       ((EGLSync)0)
#define EGL_NO_IMAGE      ((EGLImage)0)
#define EGL_NO_DISPLAY    ((EGLDisplay)0)
#define EGL_NO_SURFACE    ((EGLSurface)0)
#define EGL_FALSE         0
#define EGL_TRUE          1
#define EGL_CONDITION_SATISFIED 0x30F6

/* ---- EGL 1.5 sync stubs ------------------------------------------ */

EGLSync eglCreateSync(EGLDisplay dpy, EGLenum type, const EGLAttrib *attrib_list)
{
    (void)dpy; (void)type; (void)attrib_list;
    return EGL_NO_SYNC;
}

EGLBoolean eglDestroySync(EGLDisplay dpy, EGLSync sync)
{
    (void)dpy; (void)sync;
    return EGL_TRUE;
}

EGLint eglClientWaitSync(EGLDisplay dpy, EGLSync sync, EGLint flags, EGLTimeKHR timeout)
{
    (void)dpy; (void)sync; (void)flags; (void)timeout;
    return EGL_CONDITION_SATISFIED;
}

EGLBoolean eglWaitSync(EGLDisplay dpy, EGLSync sync, EGLint flags)
{
    (void)dpy; (void)sync; (void)flags;
    return EGL_TRUE;
}

EGLBoolean eglGetSyncAttrib(EGLDisplay dpy, EGLSync sync, EGLAttrib attribute, EGLAttrib *value)
{
    (void)dpy; (void)sync; (void)attribute; (void)value;
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
