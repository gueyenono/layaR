//! The envelope every `rs_*` entry point returns (plan D4).
//!
//! R receives `list(ok, value, error_kind, error_message, warnings)` and raises the error itself,
//! as a classed condition (`laya_error_<kind>`). Errors never unwind across the FFI boundary:
//! a `LayaError`, a bridge error and even a Rust panic all come back as `ok = FALSE`.

use crate::logging;
use extendr_api::prelude::*;
use laya::LayaError;
use std::panic::{AssertUnwindSafe, catch_unwind};

/// Any failure the bridge reports to R.
#[derive(Debug)]
pub enum BridgeError {
    /// An error from the laya engine, passed through with its own message.
    Laya(LayaError),
    /// A failure in the bridge itself (bad JSON from R, a closed engine, ...).
    Bridge { kind: &'static str, message: String },
}

impl BridgeError {
    pub fn new(kind: &'static str, message: impl Into<String>) -> Self {
        BridgeError::Bridge {
            kind,
            message: message.into(),
        }
    }

    /// The snake_case kind R appends to `laya_error_`.
    pub fn kind(&self) -> &'static str {
        match self {
            BridgeError::Laya(e) => laya_kind(e),
            BridgeError::Bridge { kind, .. } => kind,
        }
    }

    pub fn message(&self) -> String {
        match self {
            BridgeError::Laya(e) => e.to_string(),
            BridgeError::Bridge { message, .. } => message.clone(),
        }
    }
}

impl From<LayaError> for BridgeError {
    fn from(e: LayaError) -> Self {
        BridgeError::Laya(e)
    }
}

impl From<serde_json::Error> for BridgeError {
    fn from(e: serde_json::Error) -> Self {
        BridgeError::new("bridge_json", format!("invalid JSON from R: {e}"))
    }
}

/// Exhaustive on purpose: a new upstream variant breaks the build here, so it gets a kind
/// instead of silently falling into a catch-all.
pub fn laya_kind(e: &LayaError) -> &'static str {
    match e {
        LayaError::Io(_) => "io",
        LayaError::Json(_) => "json",
        LayaError::ArtifactsNotFound { .. } => "artifacts_not_found",
        LayaError::DirectoryNotFound { .. } => "directory_not_found",
        LayaError::MissingFile { .. } => "missing_file",
        LayaError::Download(_) => "download",
        LayaError::Tokenizer(_) => "tokenizer",
        LayaError::Onnx(_) => "onnx",
        LayaError::InvalidQuestion(_) => "invalid_question",
        LayaError::InvalidConfig(_) => "invalid_config",
        LayaError::CheckpointMismatch(_) => "checkpoint_mismatch",
        LayaError::NoMarkers { .. } => "no_markers",
        LayaError::InvalidState(_) => "invalid_state",
        LayaError::UnsupportedAggregate(_) => "unsupported_aggregate",
        LayaError::InvalidWindow(_) => "invalid_window",
        LayaError::NotSupported(_) => "not_supported",
        LayaError::InvalidMinConfidence(_) => "invalid_min_confidence",
    }
}

pub type BResult<T> = std::result::Result<T, BridgeError>;

/// Run `f`, collecting laya's `log` warnings, and wrap the outcome in the R envelope.
pub fn envelope(f: impl FnOnce() -> BResult<Robj>) -> Robj {
    logging::install();
    logging::drain();
    let outcome = catch_unwind(AssertUnwindSafe(f)).unwrap_or_else(|payload| {
        let message = payload
            .downcast_ref::<&str>()
            .map(|s| s.to_string())
            .or_else(|| payload.downcast_ref::<String>().cloned())
            .unwrap_or_else(|| "unknown panic".to_string());
        Err(BridgeError::new(
            "bridge_panic",
            format!("internal error (Rust panic): {message}"),
        ))
    });
    let warnings: Robj = Strings::from_values(logging::drain()).into();
    let (ok, value, kind, message): (bool, Robj, Robj, Robj) = match outcome {
        Ok(value) => (true, value, ().into(), ().into()),
        Err(e) => (false, ().into(), e.kind().into(), e.message().into()),
    };
    List::from_names_and_values(
        ["ok", "value", "error_kind", "error_message", "warnings"],
        [ok.into(), value, kind, message, warnings],
    )
    .expect("five names and five values")
    .into()
}
