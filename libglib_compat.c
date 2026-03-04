/*
 * GLib compatibility shim for Sailfish OS.
 * Provides g_once_init_enter_pointer / g_once_init_leave_pointer which were
 * added in GLib 2.74 but are absent from the Jolla GLib 2.78.4 build.
 *
 * The underlying g_once_init_enter / g_once_init_leave symbols come from
 * the SFOS libglib-2.0.so.0 that is already loaded at runtime.
 * On 64-bit ARM, gsize == uintptr_t == sizeof(pointer), so the pointer
 * variants are functionally identical to the size-typed variants.
 */
#include <stdint.h>

/* These resolve to SFOS libglib-2.0.so.0 at runtime */
extern int  g_once_init_enter (volatile uintptr_t *location);
extern void g_once_init_leave (volatile uintptr_t *location, uintptr_t result);

int g_once_init_enter_pointer(volatile void **location)
{
    return g_once_init_enter((volatile uintptr_t *)location);
}

void g_once_init_leave_pointer(volatile void **location, void *result)
{
    g_once_init_leave((volatile uintptr_t *)location, (uintptr_t)result);
}
