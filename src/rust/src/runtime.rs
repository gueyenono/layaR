//! Loading ONNX Runtime at runtime (`ort`'s `load-dynamic`).
//!
//! layaR builds without linking ONNX Runtime. R finds or downloads the shared library
//! (R/runtime.R) and loads it here once per process, before the first engine is created.
//! `ort` can't swap libraries after one is loaded, so later calls report the loaded one.
//!
//! `ort` 2.0.0-rc.15 checks the library itself (it opens, exports `OrtGetApiBase`, and is new
//! enough) and, unlike rc.13, a failed load can be retried in the same process. The environment
//! built from the loaded library is kept here and handed to every engine
//! (`LayaOptions::environment`), since `ort` allows one environment per process.

use crate::envelope::{BResult, BridgeError, envelope};
use extendr_api::prelude::*;
use serde_json::json;
use sha2::{Digest, Sha512};
use std::io::Read;
use std::sync::{Mutex, OnceLock};

/// Path and version of the loaded library.
static LOADED: OnceLock<(String, String)> = OnceLock::new();
/// The process's ONNX Runtime environment, built once the library is loaded.
static ENVIRONMENT: OnceLock<ort::environment::Environment> = OnceLock::new();
/// Serializes loading, so two calls can't race between `init_from` and `LOADED.set`.
static LOAD_LOCK: Mutex<()> = Mutex::new(());

fn info_json((path, version): &(String, String)) -> Robj {
    json!({ "path": path, "version": version, "build_info": ort::info() })
        .to_string()
        .into()
}

fn load_error(message: String) -> BridgeError {
    BridgeError::new("runtime_load", message)
}

/// The version string of the library at `path`, which `ort` has already loaded and checked.
fn library_version(path: &str) -> String {
    // SAFETY: `ort` loaded this library successfully, so it opens and exports `OrtGetApiBase`;
    // that takes no arguments, and the version string it points to is static and owned by ONNX
    // Runtime. Opening it again only bumps the loader's reference count.
    unsafe {
        let Ok(lib) = libloading::Library::new(path) else { return String::new() };
        let Ok(get_base) =
            lib.get::<unsafe extern "system" fn() -> *const ort::sys::OrtApiBase>(b"OrtGetApiBase")
        else {
            return String::new();
        };
        let base = get_base();
        if base.is_null() {
            return String::new();
        }
        let v = ((*base).GetVersionString)();
        if v.is_null() {
            String::new()
        } else {
            std::ffi::CStr::from_ptr(v).to_string_lossy().into_owned()
        }
    }
}

/// The environment built when ONNX Runtime was loaded, for `LayaOptions::environment`.
pub(crate) fn environment() -> Option<ort::environment::Environment> {
    ENVIRONMENT.get().cloned()
}

/// Load the ONNX Runtime library at `path`, or report the one already loaded.
/// @noRd
#[extendr]
fn rs_runtime_load(path: &str) -> Robj {
    envelope(|| {
        let _guard = LOAD_LOCK
            .lock()
            .map_err(|_| BridgeError::new("bridge_panic", "runtime lock poisoned by an earlier panic"))?;
        if let Some(loaded) = LOADED.get() {
            return Ok(info_json(loaded));
        }
        let builder = ort::init_from(path).map_err(|e| load_error(e.to_string()))?;
        if ENVIRONMENT.get().is_none() {
            let env = builder
                .with_name("layaR")
                .build()
                .map_err(|e| load_error(format!("could not create the ONNX Runtime environment: {e}")))?;
            let _ = ENVIRONMENT.set(env);
        }
        let loaded = LOADED.get_or_init(|| (path.to_string(), library_version(path)));
        Ok(info_json(loaded))
    })
}

/// The path of the loaded ONNX Runtime library, or NULL.
/// @noRd
#[extendr]
fn rs_runtime_loaded() -> Robj {
    match LOADED.get() {
        Some((p, _)) => p.as_str().into(),
        None => ().into(),
    }
}

fn sha512_hex(path: &str) -> BResult<String> {
    let mut file = std::fs::File::open(path)
        .map_err(|e| BridgeError::new("io", format!("can't read {path}: {e}")))?;
    let mut hasher = Sha512::new();
    let mut buf = vec![0u8; 1 << 20];
    loop {
        let n = file
            .read(&mut buf)
            .map_err(|e| BridgeError::new("io", format!("can't read {path}: {e}")))?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(hasher.finalize().iter().map(|b| format!("{b:02x}")).collect())
}

/// SHA-512 of a file, as lowercase hex.
/// @noRd
#[extendr]
fn rs_file_sha512(path: &str) -> Robj {
    envelope(|| Ok(sha512_hex(path)?.into()))
}

extendr_module! {
    mod runtime;
    fn rs_runtime_load;
    fn rs_runtime_loaded;
    fn rs_file_sha512;
}
