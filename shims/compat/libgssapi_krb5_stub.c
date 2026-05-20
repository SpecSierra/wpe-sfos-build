/*
 * Minimal GSSAPI stub for Sailfish OS.
 * libsoup-3.0 links against libgssapi_krb5 for HTTP Negotiate/SPNEGO auth.
 * SFOS has no Kerberos infrastructure, so these all return GSS_S_UNAVAILABLE.
 * The symbols are versioned @gssapi_krb5_2_MIT via the linker map file.
 */
#include <stddef.h>
#include <stdint.h>

typedef unsigned int    OM_uint32;
typedef void           *gss_ctx_id_t;
typedef void           *gss_name_t;
typedef void           *gss_cred_id_t;
typedef struct { uint32_t length; void *elements; } gss_OID_desc, *gss_OID;
typedef struct { size_t   length; void *value;    } gss_buffer_desc, *gss_buffer_t;

#define GSS_S_COMPLETE    0u
#define GSS_S_UNAVAILABLE ((OM_uint32)0x00030000u)
#define GSS_C_NO_BUFFER   ((gss_buffer_t)0)

/* Exported global OID – callers only check pointer equality, never dereference */
static gss_OID_desc _gss_c_nt_hostbased = { 0, NULL };
gss_OID GSS_C_NT_HOSTBASED_SERVICE = &_gss_c_nt_hostbased;

OM_uint32 gss_delete_sec_context(OM_uint32 *minor, gss_ctx_id_t *ctx,
                                  gss_buffer_t output_token)
{
    if (minor) *minor = 0;
    if (ctx)   *ctx   = NULL;
    (void)output_token;
    return GSS_S_UNAVAILABLE;
}

OM_uint32 gss_display_status(OM_uint32 *minor, OM_uint32 status_value,
                              int status_type, gss_OID mech_type,
                              OM_uint32 *message_context, gss_buffer_t status_string)
{
    if (minor)           *minor           = 0;
    if (message_context) *message_context = 0;
    if (status_string)  { status_string->length = 0; status_string->value = NULL; }
    (void)status_value; (void)status_type; (void)mech_type;
    return GSS_S_UNAVAILABLE;
}

OM_uint32 gss_import_name(OM_uint32 *minor, gss_buffer_t input_name_buffer,
                           gss_OID input_name_type, gss_name_t *output_name)
{
    if (minor)       *minor       = 0;
    if (output_name) *output_name = NULL;
    (void)input_name_buffer; (void)input_name_type;
    return GSS_S_UNAVAILABLE;
}

OM_uint32 gss_init_sec_context(OM_uint32 *minor, gss_cred_id_t initiator_cred,
                                gss_ctx_id_t *context_handle,
                                gss_name_t target_name, gss_OID mech_type,
                                OM_uint32 req_flags, OM_uint32 time_req,
                                void *input_chan_bindings,
                                gss_buffer_t input_token,
                                gss_OID *actual_mech_type,
                                gss_buffer_t output_token,
                                OM_uint32 *ret_flags, OM_uint32 *time_rec)
{
    if (minor)            *minor            = 0;
    if (context_handle)   *context_handle   = NULL;
    if (actual_mech_type) *actual_mech_type = NULL;
    if (output_token)    { output_token->length = 0; output_token->value = NULL; }
    if (ret_flags)        *ret_flags        = 0;
    if (time_rec)         *time_rec         = 0;
    (void)initiator_cred; (void)target_name; (void)mech_type;
    (void)req_flags; (void)time_req; (void)input_chan_bindings; (void)input_token;
    return GSS_S_UNAVAILABLE;
}

OM_uint32 gss_release_buffer(OM_uint32 *minor, gss_buffer_t buffer)
{
    if (minor)  *minor = 0;
    if (buffer) { buffer->length = 0; buffer->value = NULL; }
    return GSS_S_COMPLETE;
}

OM_uint32 gss_release_name(OM_uint32 *minor, gss_name_t *name)
{
    if (minor) *minor = 0;
    if (name)  *name  = NULL;
    return GSS_S_COMPLETE;
}
