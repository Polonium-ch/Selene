use crate::{crypto, identity::Identity};
use std::ffi::CStr;
use std::os::raw::c_char;
use std::path::Path;
use std::ptr;

#[repr(C)]
pub struct SeleneCryptoBuffer {
    pub ptr: *mut u8,
    pub len: usize,
}

fn buffer_from_vec(v: Vec<u8>) -> SeleneCryptoBuffer {
    if v.is_empty() {
        return SeleneCryptoBuffer {
            ptr: ptr::null_mut(),
            len: 0,
        };
    }
    let boxed = v.into_boxed_slice();
    let len = boxed.len();
    let ptr = Box::into_raw(boxed) as *mut u8;
    SeleneCryptoBuffer { ptr, len }
}

fn empty_buffer() -> SeleneCryptoBuffer {
    SeleneCryptoBuffer {
        ptr: ptr::null_mut(),
        len: 0,
    }
}

/// SAFETY: `s` must be NULL or a valid, NUL-terminated, UTF-8 C string
/// that outlives this call - true for every caller in this crate, which
/// only ever receives strings straight from Objective-C++ `.UTF8String`.
unsafe fn str_from_c(s: *const c_char) -> Option<&'static str> {
    if s.is_null() {
        return None;
    }
    CStr::from_ptr(s).to_str().ok()
}

/// SAFETY: `data`/`len` must describe a valid, readable byte buffer that
/// outlives this call - true for every caller in this crate.
unsafe fn slice_from_c<'a>(data: *const u8, len: usize) -> &'a [u8] {
    if data.is_null() || len == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(data, len)
    }
}

#[no_mangle]
pub extern "C" fn selene_crypto_free_buffer(buf: SeleneCryptoBuffer) {
    if buf.ptr.is_null() {
        return;
    }
    unsafe {
        let slice = std::slice::from_raw_parts_mut(buf.ptr, buf.len);
        drop(Box::from_raw(slice as *mut [u8]));
    }
}

pub struct SeleneIdentity(Identity);

#[no_mangle]
pub extern "C" fn selene_identity_shared(support_dir_utf8: *const c_char) -> *mut SeleneIdentity {
    let dir = match unsafe { str_from_c(support_dir_utf8) } {
        Some(d) => d,
        None => return ptr::null_mut(),
    };
    match Identity::load_or_create(Path::new(dir)) {
        Some(id) => Box::into_raw(Box::new(SeleneIdentity(id))),
        None => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn selene_identity_certificate_pem(
    identity: *const SeleneIdentity,
) -> SeleneCryptoBuffer {
    match unsafe { identity.as_ref() } {
        Some(id) => buffer_from_vec(id.0.certificate_pem.clone().into_bytes()),
        None => empty_buffer(),
    }
}

#[no_mangle]
pub extern "C" fn selene_identity_unique_id(identity: *const SeleneIdentity) -> SeleneCryptoBuffer {
    match unsafe { identity.as_ref() } {
        Some(id) => buffer_from_vec(id.0.unique_id.clone().into_bytes()),
        None => empty_buffer(),
    }
}

#[no_mangle]
pub extern "C" fn selene_identity_sign_sha256(
    identity: *const SeleneIdentity,
    message: *const u8,
    message_len: usize,
) -> SeleneCryptoBuffer {
    let id = match unsafe { identity.as_ref() } {
        Some(id) => id,
        None => return empty_buffer(),
    };
    let message = unsafe { slice_from_c(message, message_len) };
    buffer_from_vec(id.0.sign_sha256(message))
}

#[no_mangle]
pub extern "C" fn selene_identity_pkcs12(
    identity: *const SeleneIdentity,
    password_utf8: *const c_char,
) -> SeleneCryptoBuffer {
    let id = match unsafe { identity.as_ref() } {
        Some(id) => id,
        None => return empty_buffer(),
    };
    let password = match unsafe { str_from_c(password_utf8) } {
        Some(p) => p,
        None => return empty_buffer(),
    };
    match id.0.pkcs12(password) {
        Some(data) => buffer_from_vec(data),
        None => empty_buffer(),
    }
}

#[no_mangle]
pub extern "C" fn selene_crypto_random_bytes(length: usize) -> SeleneCryptoBuffer {
    buffer_from_vec(crypto::random_bytes(length))
}

#[no_mangle]
pub extern "C" fn selene_crypto_sha1(data: *const u8, len: usize) -> SeleneCryptoBuffer {
    buffer_from_vec(crypto::sha1(unsafe { slice_from_c(data, len) }))
}

#[no_mangle]
pub extern "C" fn selene_crypto_sha256(data: *const u8, len: usize) -> SeleneCryptoBuffer {
    buffer_from_vec(crypto::sha256(unsafe { slice_from_c(data, len) }))
}

#[no_mangle]
pub extern "C" fn selene_crypto_aes128_ecb_encrypt(
    plaintext: *const u8,
    plaintext_len: usize,
    key: *const u8,
) -> SeleneCryptoBuffer {
    let plaintext = unsafe { slice_from_c(plaintext, plaintext_len) };
    let key = unsafe { slice_from_c(key, 16) };
    buffer_from_vec(crypto::aes128_ecb_encrypt(plaintext, key))
}

#[no_mangle]
pub extern "C" fn selene_crypto_aes128_ecb_decrypt(
    ciphertext: *const u8,
    ciphertext_len: usize,
    key: *const u8,
) -> SeleneCryptoBuffer {
    let ciphertext = unsafe { slice_from_c(ciphertext, ciphertext_len) };
    let key = unsafe { slice_from_c(key, 16) };
    buffer_from_vec(crypto::aes128_ecb_decrypt(ciphertext, key))
}

#[no_mangle]
pub extern "C" fn selene_crypto_signature_from_certificate_pem(
    certificate_pem_utf8: *const c_char,
) -> SeleneCryptoBuffer {
    let pem = match unsafe { str_from_c(certificate_pem_utf8) } {
        Some(p) => p,
        None => return empty_buffer(),
    };
    match crypto::signature_from_certificate_pem(pem) {
        Some(sig) => buffer_from_vec(sig),
        None => empty_buffer(),
    }
}

#[no_mangle]
pub extern "C" fn selene_crypto_verify_signature(
    signature: *const u8,
    signature_len: usize,
    data: *const u8,
    data_len: usize,
    certificate_pem_utf8: *const c_char,
) -> bool {
    let pem = match unsafe { str_from_c(certificate_pem_utf8) } {
        Some(p) => p,
        None => return false,
    };
    let signature = unsafe { slice_from_c(signature, signature_len) };
    let data = unsafe { slice_from_c(data, data_len) };
    crypto::verify_signature(signature, data, pem)
}
