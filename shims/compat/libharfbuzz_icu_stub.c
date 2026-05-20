/*
 * Minimal libharfbuzz-icu stub for Sailfish OS.
 * WPEWebKit calls hb_icu_script_to_script() to convert ICU script codes
 * to HarfBuzz 4-character tags. The Ubuntu build of libharfbuzz-icu links
 * against libicuuc.so.74 which is not on SFOS (which has ICU 70).
 * This stub returns HB_SCRIPT_UNKNOWN (0) for all inputs — text rendering
 * may lose script-specific shaping hints but will not crash.
 */
#include <stdint.h>

typedef uint32_t hb_script_t;
#define HB_SCRIPT_UNKNOWN ((hb_script_t)0)

/* UScriptCode from ICU — just an int */
typedef int UScriptCode;

hb_script_t hb_icu_script_to_script(UScriptCode script_code)
{
    (void)script_code;
    return HB_SCRIPT_UNKNOWN;
}
