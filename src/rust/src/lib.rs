//! layaR's bridge to laya-onnx (plan section 6).
//!
//! Thin by design: JSON in, JSON out, no inference logic. Every exported function except the
//! three plain predicates returns the envelope from `envelope.rs`; R unwraps it and raises
//! classed conditions. Function names start with `rs_`: they are internal and wrapped in R.

mod envelope;
mod logging;
mod options;
mod questions;
mod results;
mod text;

use envelope::{BResult, BridgeError, envelope};
use extendr_api::prelude::*;
use laya::{LayaEngine, LayaOptions, LayaPresets, ModelArtifacts, ModelLayout, ModelPaths};
use serde_json::{Value, json};
use std::sync::{Arc, Mutex};

/// laya-onnx's git revision; keep in sync with `Cargo.toml`.
const LAYA_ONNX_REV: &str = "80a1da1fa5448ea12163f4d977935625a0aea670";
const LAYA_ONNX_VERSION: &str = "0.1.0";
const ORT_VERSION: &str = "2.0.0-rc.13";

/// The engine R holds through an external pointer. The `Option` lets `rs_engine_close` free the
/// ONNX session (over 1 GB) before R's garbage collector runs the finalizer.
pub struct EngineHandle {
    inner: Mutex<Option<Arc<LayaEngine>>>,
}

impl std::fmt::Debug for EngineHandle {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("EngineHandle")
    }
}

fn closed() -> BridgeError {
    BridgeError::new(
        "bridge_engine_closed",
        "this engine has been closed or did not survive serialization; create a new one",
    )
}

/// Borrow the engine out of an R object. A NULL pointer (after `readRDS()`), a wrong object, or
/// a closed engine is an error, never a dereference.
fn engine_from(robj: &Robj) -> BResult<Arc<LayaEngine>> {
    let ptr: &ExternalPtr<EngineHandle> = robj.try_into().map_err(|_| closed())?;
    let guard = ptr
        .inner
        .lock()
        .map_err(|_| BridgeError::new("bridge_panic", "engine lock poisoned by an earlier panic"))?;
    guard.as_ref().cloned().ok_or_else(closed)
}

fn json_robj(v: &Value) -> Robj {
    v.to_string().into()
}

fn parse_state(json: &str) -> BResult<Value> {
    Ok(serde_json::from_str(json)?)
}

/// Load an exported checkpoint directory.
/// @noRd
#[extendr]
fn rs_engine_new(model_dir: &str, options_json: &str) -> Robj {
    envelope(|| {
        let o = options::engine_options(options_json)?;
        let engine = LayaEngine::create(LayaOptions {
            model_directory: Some(model_dir.into()),
            intra_op_threads: o.intra_op_threads,
            inter_op_threads: o.inter_op_threads,
            lang_temperatures: o.lang_temperatures,
            ..LayaOptions::default()
        })?;
        let handle = EngineHandle {
            inner: Mutex::new(Some(Arc::new(engine))),
        };
        Ok(ExternalPtr::new(handle).into())
    })
}

/// Checkpoint, layout, paths and sequence budgets of a loaded engine.
/// @noRd
#[extendr]
fn rs_engine_info(engine: Robj) -> Robj {
    envelope(|| {
        let e = engine_from(&engine)?;
        let a = e.artifacts();
        let c = e.config();
        let paths = match &a.model {
            ModelPaths::Fused { model_path } => json!({ "model": model_path }),
            ModelPaths::Split { encoder_path, head_path } => {
                json!({ "encoder": encoder_path, "head": head_path })
            }
        };
        let mut buckets: Vec<(&String, &f64)> = c.temperature_by_options.iter().collect();
        buckets.sort_by(|a, b| a.0.cmp(b.0));
        let info = json!({
            "checkpoint": e.checkpoint().map(|k| k.subdir()),
            "layout": match a.layout() { ModelLayout::Fused => "fused", ModelLayout::Split => "split" },
            "directory": a.directory,
            "model_paths": paths,
            "config_path": a.config_path,
            "tokenizer_path": a.tokenizer_path,
            "encoder": c.encoder,
            "max_len": c.max_len,
            "head_max_len": c.head_max_len,
            "temperature": c.temperature,
            "temperature_by_options": buckets
                .into_iter()
                .map(|(k, v)| (k.clone(), json!(v)))
                .collect::<serde_json::Map<String, Value>>(),
            "clamped_temperatures": c.clamped_temperatures,
            "lang_temperature_languages": e.lang_temperatures().languages(),
        });
        Ok(json_robj(&info))
    })
}

/// Free the engine's ONNX session now. Idempotent.
/// @noRd
#[extendr]
fn rs_engine_close(engine: Robj) -> Robj {
    envelope(|| {
        let ptr: &ExternalPtr<EngineHandle> = (&engine).try_into().map_err(|_| closed())?;
        if let Ok(mut guard) = ptr.inner.lock() {
            guard.take();
        }
        Ok(().into())
    })
}

/// TRUE when the engine can still run (not closed, not a stale pointer).
/// @noRd
#[extendr]
fn rs_engine_is_live(engine: Robj) -> bool {
    engine_from(&engine).is_ok()
}

/// Answer every question about one state.
/// @noRd
#[extendr]
fn rs_predict(engine: Robj, state_json: &str, questions_json: &str, options_json: &str) -> Robj {
    envelope(|| {
        let e = engine_from(&engine)?;
        let state = parse_state(state_json)?;
        let questions = questions::parse_questions(questions_json)?;
        let opts = options::predict_options(options_json)?;
        let result = e.predict_with_options(state, &questions, &opts)?;
        Ok(json_robj(&results::encode_result(&result)))
    })
}

/// Answer every question about every state; `states_json` is a JSON array.
/// @noRd
#[extendr]
fn rs_predict_batch(engine: Robj, states_json: &str, questions_json: &str, options_json: &str) -> Robj {
    envelope(|| {
        let e = engine_from(&engine)?;
        let states = match parse_state(states_json)? {
            Value::Array(states) => states,
            _ => return Err(BridgeError::new("bridge_json", "states must be a JSON array")),
        };
        let questions = questions::parse_questions(questions_json)?;
        let opts = options::batch_options(options_json)?;
        let out = e.predict_batch(&states, &questions, &opts)?;
        let encoded: Vec<Value> = out.iter().map(results::encode_result).collect();
        Ok(json_robj(&Value::Array(encoded)))
    })
}

/// Scan one long state in overlapping windows.
/// @noRd
#[extendr]
fn rs_predict_long(engine: Robj, state_json: &str, questions_json: &str, options_json: &str) -> Robj {
    envelope(|| {
        let e = engine_from(&engine)?;
        let state = parse_state(state_json)?;
        let questions = questions::parse_questions(questions_json)?;
        let opts = options::long_options(options_json)?;
        let result = e.predict_long(state, &questions, &opts)?;
        Ok(json_robj(&results::encode_result(&result)))
    })
}

/// Validate Python-format questions without a model; returns them normalized.
/// @noRd
#[extendr]
fn rs_questions_validate(questions_json: &str) -> Robj {
    envelope(|| {
        let set = questions::parse_questions(questions_json)?;
        Ok(json_robj(&questions::encode_questions(&set)))
    })
}

/// A built-in question set. `categories_json` is an ordered `{label: description}` object or
/// null (email preset only).
/// @noRd
#[extendr]
fn rs_preset(name: &str, categories_json: &str) -> Robj {
    envelope(|| {
        let categories: Value = if categories_json.trim().is_empty() {
            Value::Null
        } else {
            serde_json::from_str(categories_json)?
        };
        if !categories.is_null() && name != "email" {
            return Err(BridgeError::new(
                "bridge_invalid_option",
                format!("only the email preset takes categories, not '{name}'"),
            ));
        }
        let set = match name {
            "triage" => LayaPresets::triage(),
            "guard" => LayaPresets::guard(),
            "moderation" => LayaPresets::moderation(),
            "router" => LayaPresets::router(),
            "email" => match &categories {
                Value::Null => LayaPresets::email(None::<Vec<(&str, &str)>>),
                Value::Object(map) => {
                    let mut pairs = Vec::with_capacity(map.len());
                    for (label, desc) in map {
                        let desc = desc.as_str().ok_or_else(|| {
                            BridgeError::new(
                                "bridge_invalid_option",
                                format!("email category '{label}' needs a string description"),
                            )
                        })?;
                        pairs.push((label.as_str(), desc));
                    }
                    LayaPresets::email(Some(pairs))
                }
                _ => {
                    return Err(BridgeError::new(
                        "bridge_invalid_option",
                        "categories must be an object {label: description}",
                    ));
                }
            },
            other => {
                return Err(BridgeError::new(
                    "bridge_invalid_option",
                    format!("unknown preset '{other}' (expected triage, email, guard, moderation or router)"),
                ));
            }
        };
        Ok(json_robj(&questions::encode_questions(&set)))
    })
}

/// Valid `min_confidence` bucket names.
/// @noRd
#[extendr]
fn rs_bucket_keys() -> Vec<String> {
    laya::bucket_keys()
}

/// TRUE when a directory holds a complete export (either layout).
/// @noRd
#[extendr]
fn rs_artifacts_complete(dir: &str) -> bool {
    ModelArtifacts::is_complete(dir)
}

/// Language analysis of each state in a JSON array (no model needed).
/// @noRd
#[extendr]
fn rs_detect_language(states_json: &str) -> Robj {
    envelope(|| Ok(json_robj(&text::detect_languages(states_json)?)))
}

/// Python's `clean_email_body` over a JSON array of bodies; `max_chars` is signed, as in Python.
/// @noRd
#[extendr]
fn rs_clean_email(bodies_json: &str, max_chars: f64) -> Robj {
    envelope(|| Ok(json_robj(&text::clean_emails(bodies_json, max_chars as i64)?)))
}

/// Python's `email_state`. An empty `sender` means none.
/// @noRd
#[extendr]
fn rs_email_state(subject: &str, body: &str, sender: &str, clean: bool, max_chars: f64, extra_json: &str) -> Robj {
    envelope(|| {
        let sender = (!sender.is_empty()).then_some(sender);
        let state = text::email_state(subject, body, sender, clean, max_chars as i64, extra_json)?;
        Ok(json_robj(&state))
    })
}

/// Versions of the bridge and the Rust libraries it is built on.
/// @noRd
#[extendr]
fn rs_versions() -> Robj {
    let names = ["layaR_bridge", "laya_onnx", "laya_onnx_rev", "ort"];
    let values = [env!("CARGO_PKG_VERSION"), LAYA_ONNX_VERSION, LAYA_ONNX_REV, ORT_VERSION];
    let mut out: Robj = Strings::from_values(values).into();
    out.set_names(names).expect("names match values");
    out
}

extendr_module! {
    mod laya_r;
    fn rs_engine_new;
    fn rs_engine_info;
    fn rs_engine_close;
    fn rs_engine_is_live;
    fn rs_predict;
    fn rs_predict_batch;
    fn rs_predict_long;
    fn rs_questions_validate;
    fn rs_preset;
    fn rs_bucket_keys;
    fn rs_artifacts_complete;
    fn rs_detect_language;
    fn rs_clean_email;
    fn rs_email_state;
    fn rs_versions;
}
