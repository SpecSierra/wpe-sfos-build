use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::slice;

use adblock::engine::Engine as AdblockEngine;
use adblock::lists::{FilterSet, ParseOptions};
use adblock::request::Request;

pub struct AtlanticAdblockEngine {
    engine: AdblockEngine,
}

#[repr(C)]
pub struct MatchResult {
    pub matched: bool,
    pub important: bool,
    pub redirect: *mut c_char,
    pub exception: *mut c_char,
}

#[repr(C)]
pub struct CosmeticResult {
    pub hide_selectors: *const c_char,
    pub injected_script: *const c_char,
    pub generated_css: *const c_char,
}

fn to_c_string(s: &str) -> *mut c_char {
    CString::new(s)
        .unwrap_or_else(|_| CString::new("").unwrap())
        .into_raw()
}

unsafe fn str_from_c<'a>(ptr: *const c_char) -> &'a str {
    if ptr.is_null() {
        return "";
    }
    CStr::from_ptr(ptr).to_str().unwrap_or("")
}

#[no_mangle]
pub unsafe extern "C" fn atlantic_adblock_create_from_cache(
    data: *const u8,
    len: usize,
) -> *mut AtlanticAdblockEngine {
    if data.is_null() || len == 0 {
        return std::ptr::null_mut();
    }
    let bytes = slice::from_raw_parts(data, len);
    let mut engine = AdblockEngine::from_filter_set(FilterSet::new(true), false);
    match engine.deserialize(bytes) {
        Ok(()) => Box::into_raw(Box::new(AtlanticAdblockEngine { engine })),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn atlantic_adblock_create_from_lists(
    lists: *const *const c_char,
    count: i32,
) -> *mut AtlanticAdblockEngine {
    if lists.is_null() || count <= 0 {
        return std::ptr::null_mut();
    }

    let mut filter_set = FilterSet::new(true);
    let list_slice = slice::from_raw_parts(lists, count as usize);

    for &ptr in list_slice {
        if ptr.is_null() {
            continue;
        }
        let path = CStr::from_ptr(ptr).to_str().unwrap_or("");
        if let Ok(text) = std::fs::read_to_string(path) {
            let fmt = if path.contains("hosts") {
                adblock::lists::FilterFormat::Hosts
            } else {
                adblock::lists::FilterFormat::Standard
            };
            let opts = ParseOptions {
                format: fmt,
                ..ParseOptions::default()
            };
            filter_set.add_filter_list(&text, opts);
        }
    }

    let engine = AdblockEngine::from_filter_set(filter_set, true);
    Box::into_raw(Box::new(AtlanticAdblockEngine { engine }))
}

#[no_mangle]
pub unsafe extern "C" fn atlantic_adblock_destroy(engine: *mut AtlanticAdblockEngine) {
    if !engine.is_null() {
        drop(Box::from_raw(engine));
    }
}

#[no_mangle]
pub unsafe extern "C" fn atlantic_adblock_serialize(
    engine: *mut AtlanticAdblockEngine,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    if engine.is_null() || out.is_null() || out_len.is_null() {
        return 0;
    }
    let eng = &(*engine).engine;
    let data = eng.serialize();
    let len = data.len();
    let ptr = data.leak();
    *out = ptr.as_mut_ptr();
    *out_len = len;
    1
}

#[no_mangle]
pub unsafe extern "C" fn atlantic_adblock_free_buffer(buf: *mut u8, len: usize) {
    if !buf.is_null() && len > 0 {
        drop(Vec::from_raw_parts(buf, len, len));
    }
}

#[no_mangle]
pub unsafe extern "C" fn atlantic_adblock_match_network(
    engine: *mut AtlanticAdblockEngine,
    src_url: *const c_char,
    req_url: *const c_char,
    resource_type: *const c_char,
    third_party_raw: i32,
) -> MatchResult {
    if engine.is_null() || req_url.is_null() {
        return MatchResult {
            matched: false,
            important: false,
            redirect: std::ptr::null_mut(),
            exception: std::ptr::null_mut(),
        };
    }

    let eng = &(*engine).engine;
    let src = str_from_c(src_url);
    let req = str_from_c(req_url);
    let rtype = str_from_c(resource_type);
    let third_party = third_party_raw != 0;

    if rtype.is_empty() {
        return MatchResult {
            matched: false,
            important: false,
            redirect: std::ptr::null_mut(),
            exception: std::ptr::null_mut(),
        };
    }

    let request = Request::preparsed(
        req,
        "",
        if src.is_empty() || third_party {
            ""
        } else {
            src
        },
        rtype,
        third_party,
    );

    let result = eng.check_network_request(&request);

    MatchResult {
        matched: result.matched,
        important: result.important,
        redirect: match &result.redirect {
            Some(s) => to_c_string(s),
            None => std::ptr::null_mut(),
        },
        exception: match &result.exception {
            Some(s) => to_c_string(s),
            None => std::ptr::null_mut(),
        },
    }
}

#[no_mangle]
pub unsafe extern "C" fn atlantic_adblock_free_match_result(result: MatchResult) {
    if !result.redirect.is_null() {
        drop(CString::from_raw(result.redirect));
    }
    if !result.exception.is_null() {
        drop(CString::from_raw(result.exception));
    }
}

#[no_mangle]
pub unsafe extern "C" fn atlantic_adblock_get_cosmetic(
    engine: *mut AtlanticAdblockEngine,
    url: *const c_char,
) -> CosmeticResult {
    if engine.is_null() || url.is_null() {
        return CosmeticResult {
            hide_selectors: std::ptr::null(),
            injected_script: std::ptr::null(),
            generated_css: std::ptr::null(),
        };
    }

    let eng = &(*engine).engine;
    let url_str = str_from_c(url);

    let resources = eng.url_cosmetic_resources(url_str);

    let hide = if resources.hide_selectors.is_empty() {
        std::ptr::null()
    } else {
        let combined: Vec<&str> = resources.hide_selectors.iter().map(|s| s.as_str()).collect();
        let joined = combined.join(", ");
        CString::new(joined).unwrap().into_raw() as *const c_char
    };

    let script = if resources.injected_script.is_empty() {
        std::ptr::null()
    } else {
        CString::new(resources.injected_script.as_str())
            .unwrap()
            .into_raw() as *const c_char
    };

    let css = if resources.procedural_actions.is_empty() {
        std::ptr::null()
    } else {
        let combined: Vec<&str> = resources.procedural_actions.iter().map(|s| s.as_str()).collect();
        let joined = combined.join("\n");
        CString::new(joined).unwrap().into_raw() as *const c_char
    };

    CosmeticResult {
        hide_selectors: hide,
        injected_script: script,
        generated_css: css,
    }
}

#[no_mangle]
pub unsafe extern "C" fn atlantic_adblock_free_cosmetic(result: CosmeticResult) {
    if !result.hide_selectors.is_null() {
        drop(CString::from_raw(result.hide_selectors as *mut c_char));
    }
    if !result.injected_script.is_null() {
        drop(CString::from_raw(result.injected_script as *mut c_char));
    }
    if !result.generated_css.is_null() {
        drop(CString::from_raw(result.generated_css as *mut c_char));
    }
}

#[no_mangle]
pub unsafe extern "C" fn atlantic_adblock_enable_tag(
    engine: *mut AtlanticAdblockEngine,
    tag: *const c_char,
) {
    if engine.is_null() || tag.is_null() {
        return;
    }
    let eng = &mut (*engine).engine;
    let tag_str = str_from_c(tag);
    eng.enable_tags(&[tag_str]);
}
