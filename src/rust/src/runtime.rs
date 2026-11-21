//! Loading ONNX Runtime at runtime (`ort`'s `load-dynamic`).
//!
//! layaR builds without linking ONNX Runtime. R finds or downloads the shared library
//! (R/runtime.R) and loads it here once per process, before the first engine is created.
//! `ort` can't swap libraries after one is loaded, so later calls report the loaded one.
//!
//! `ort` 2.0.0-rc.13 can't recover from a failed load either: its `OnceLock::get_or_try_init`
//! runs in `Once::call_once_force`, so an error still marks the slot initialized, with nothing
//! in it, and the next load reads uninitialized memory. So the library is checked here first
//! (it opens, exports `OrtGetApiBase`, and is new enough), and `ort` only sees one that loads.

use crate::envelope::{BResult, BridgeError, envelope};
use extendr_api::prelude::*;
use serde_json::json;
use sha2::{Digest, Sha512};
use std::io::Read;
use std::sync::{Mutex, OnceLock};

/// Path and version of the loaded library.
static LOADED: OnceLock<(String, String)> = OnceLock::new();
/// Set when `ort` itself failed to load a library; no further load is safe in this process.
static POISONED: OnceLock<String> = OnceLock::new();
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

/// Open the library the way `ort` will and check what `ort`'s loader checks: it opens, exports
/// `OrtGetApiBase`, and reports a version of at least `1.<ort::MINOR_VERSION>`. Returns that
/// version string. The handle is dropped afterwards; `ort` takes its own.
fn check_library(path: &str) -> BResult<String> {
    // SAFETY: loading a shared library runs its initializers; this is the library `ort` is about
    // to load anyway. `OrtGetApiBase` takes no arguments, and the version string it points to is
    // static and owned by ONNX Runtime.
    unsafe {
        let lib = libloading::Library::new(path)
            .map_err(|e| load_error(format!("failed to load from `{path}`: {e}")))?;
        let get_base = lib
            .get::<unsafe extern "system" fn() -> *const ort::sys::OrtApiBase>(b"OrtGetApiBase")
            .map_err(|_| load_error(format!("`{path}` is not ONNX Runtime (no `OrtGetApiBase`)")))?;
        let base = get_base();
        if base.is_null() {
            return Err(load_error(format!("`{path}` returned no ONNX Runtime API")));
        }
        let v = ((*base).GetVersionString)();
        let version = if v.is_null() {
            String::new()
        } else {
            std::ffi::CStr::from_ptr(v).to_string_lossy().into_owned()
        };
        // Parsed as `ort` does: the minor version, 0 when unreadable.
        let minor = version.split('.').nth(1).and_then(|m| m.parse::<u32>().ok()).unwrap_or(0);
        if minor < ort::MINOR_VERSION {
            return Err(load_error(format!(
                "`{path}` is ONNX Runtime {version}; layaR needs 1.{} or newer",
                ort::MINOR_VERSION
            )));
        }
        Ok(version)
    }
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
        if let Some(why) = POISONED.get() {
            return Err(load_error(format!(
                "an earlier attempt to load ONNX Runtime failed ({why}); restart R to try again"
            )));
        }
        let version = check_library(path)?;
        let builder = match ort::init_from(path) {
            Ok(b) => b,
            Err(e) => {
                let _ = POISONED.set(e.to_string());
                return Err(load_error(e.to_string()));
            }
        };
        builder.with_name("layaR").commit();
        let loaded = LOADED.get_or_init(|| (path.to_string(), version));
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
