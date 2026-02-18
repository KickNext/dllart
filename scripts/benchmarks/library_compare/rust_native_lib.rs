use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::sync::{Mutex, OnceLock};

const CPU_MASK: i64 = 0x7fff_ffff;
const IO_MASK32: u32 = 0xffff_ffff;
const IO_BLOCK_SIZE: usize = 1 << 20;

static IO_PAYLOAD: OnceLock<Mutex<Vec<u8>>> = OnceLock::new();

fn payload() -> &'static Mutex<Vec<u8>> {
    IO_PAYLOAD.get_or_init(|| Mutex::new(Vec::new()))
}

fn set_error(error_out: *mut *mut c_char, message: &str) {
    if error_out.is_null() {
        return;
    }
    match CString::new(message) {
        Ok(msg) => unsafe {
            *error_out = msg.into_raw();
        },
        Err(_) => unsafe {
            *error_out = std::ptr::null_mut();
        },
    }
}

fn clear_error(error_out: *mut *mut c_char) {
    if error_out.is_null() {
        return;
    }
    unsafe {
        *error_out = std::ptr::null_mut();
    }
}

fn fill_buffer(buffer: &mut [u8]) {
    let mut seed: u32 = 0xA5A5_A5A5;
    for slot in buffer.iter_mut() {
        seed ^= seed.wrapping_shl(13);
        seed ^= seed.wrapping_shr(17);
        seed ^= seed.wrapping_shl(5);
        seed &= IO_MASK32;
        *slot = (seed & 0xff) as u8;
    }
}

#[no_mangle]
pub extern "C" fn bench_init(runtime_path: *const c_char, error_out: *mut *mut c_char) -> c_int {
    let _ = runtime_path;
    clear_error(error_out);
    0
}

#[no_mangle]
pub extern "C" fn bench_cpu_work(
    iterations: i64,
    seed: i64,
    checksum_out: *mut i64,
    error_out: *mut *mut c_char,
) -> c_int {
    clear_error(error_out);
    if iterations <= 0 {
        set_error(error_out, "iterations must be > 0");
        return 1;
    }
    if checksum_out.is_null() {
        set_error(error_out, "checksum_out is null");
        return 1;
    }

    let mut x = seed & CPU_MASK;
    let mut acc: i64 = 0;
    for i in 0..iterations {
        x = (x.wrapping_mul(1_103_515_245).wrapping_add(12_345)) & CPU_MASK;
        acc = (acc.wrapping_add((x ^ i) & CPU_MASK)) & CPU_MASK;
    }

    unsafe {
        *checksum_out = acc;
    }
    0
}

#[no_mangle]
pub extern "C" fn bench_io_write(
    path: *const c_char,
    file_mb: i64,
    bytes_written_out: *mut i64,
    error_out: *mut *mut c_char,
) -> c_int {
    clear_error(error_out);
    if path.is_null() {
        set_error(error_out, "path must be non-empty");
        return 1;
    }
    if file_mb <= 0 {
        set_error(error_out, "file_mb must be > 0");
        return 1;
    }
    if bytes_written_out.is_null() {
        set_error(error_out, "bytes_written_out is null");
        return 1;
    }

    let path_string = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(v) if !v.is_empty() => v,
        _ => {
            set_error(error_out, "path must be valid UTF-8");
            return 1;
        }
    };
    let _ = path_string;

    let total_bytes = file_mb.saturating_mul(1024).saturating_mul(1024) as usize;
    let mut pattern = vec![0_u8; IO_BLOCK_SIZE];
    fill_buffer(&mut pattern);

    let mut out = vec![0_u8; total_bytes];
    let mut offset = 0usize;
    while offset < total_bytes {
        let chunk = (total_bytes - offset).min(pattern.len());
        out[offset..offset + chunk].copy_from_slice(&pattern[..chunk]);
        offset += chunk;
    }

    let lock = payload();
    let mut guard = match lock.lock() {
        Ok(g) => g,
        Err(_) => {
            set_error(error_out, "payload lock poisoned");
            return 1;
        }
    };
    *guard = out;

    unsafe {
        *bytes_written_out = total_bytes as i64;
    }
    0
}

#[no_mangle]
pub extern "C" fn bench_io_read(
    path: *const c_char,
    file_mb: i64,
    checksum_out: *mut i64,
    error_out: *mut *mut c_char,
) -> c_int {
    clear_error(error_out);
    if path.is_null() {
        set_error(error_out, "path must be non-empty");
        return 1;
    }
    if file_mb <= 0 {
        set_error(error_out, "file_mb must be > 0");
        return 1;
    }
    if checksum_out.is_null() {
        set_error(error_out, "checksum_out is null");
        return 1;
    }

    let path_string = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(v) if !v.is_empty() => v,
        _ => {
            set_error(error_out, "path must be valid UTF-8");
            return 1;
        }
    };
    let _ = path_string;

    let total_bytes = file_mb.saturating_mul(1024).saturating_mul(1024) as usize;

    let lock = payload();
    let mut guard = match lock.lock() {
        Ok(g) => g,
        Err(_) => {
            set_error(error_out, "payload lock poisoned");
            return 1;
        }
    };

    if guard.len() != total_bytes {
        set_error(error_out, "payload size mismatch");
        return 1;
    }

    let mut checksum: i64 = 0;
    for b in guard.iter() {
        checksum = checksum.wrapping_add(*b as i64);
    }

    guard.clear();
    guard.shrink_to_fit();

    unsafe {
        *checksum_out = checksum;
    }
    0
}

#[no_mangle]
pub extern "C" fn bench_shutdown() {}

#[no_mangle]
pub extern "C" fn bench_string_free(value: *mut c_char) {
    if value.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(value));
    }
}
