//! JSON from R -> laya's per-call and engine options.
//!
//! Every options object is strict: an unknown key is an error naming it, so a misspelled option
//! never silently does nothing. Values are passed through without extra validation where laya
//! validates them itself (min_confidence thresholds, token budgets), so its Python-worded errors
//! reach the user unchanged.

use crate::envelope::{BResult, BridgeError};
use laya::lang_temperatures::{LangTemperature, LangTemperatureTable, TemperatureValue};
use laya::{BatchOptions, LongOptions, MinConfidence, PredictOptions};
use serde_json::{Map, Value};

fn bad(message: String) -> BridgeError {
    BridgeError::new("bridge_invalid_option", message)
}

fn parse_object(json: &str, allowed: &[&str], what: &str) -> BResult<Map<String, Value>> {
    let value: Value = if json.trim().is_empty() {
        Value::Object(Map::new())
    } else {
        serde_json::from_str(json)?
    };
    let map = match value {
        Value::Object(map) => map,
        Value::Null => Map::new(),
        _ => return Err(bad(format!("{what} options must be an object"))),
    };
    for key in map.keys() {
        if !allowed.contains(&key.as_str()) {
            return Err(bad(format!(
                "unknown {what} option '{key}' (expected one of: {})",
                allowed.join(", ")
            )));
        }
    }
    // Explicit nulls mean "not set".
    Ok(map.into_iter().filter(|(_, v)| !v.is_null()).collect())
}

fn min_confidence(v: &Value) -> BResult<MinConfidence> {
    match v {
        Value::Number(n) => Ok(MinConfidence::Scalar(n.as_f64().unwrap_or(f64::NAN))),
        Value::Object(map) => {
            let mut thresholds = indexmap::IndexMap::new();
            for (key, value) in map {
                let t = value.as_f64().ok_or_else(|| {
                    bad(format!("min_confidence['{key}'] must be a number"))
                })?;
                thresholds.insert(key.clone(), t);
            }
            Ok(MinConfidence::Map(thresholds))
        }
        _ => Err(bad(
            "min_confidence must be a number or an object of bucket thresholds".into(),
        )),
    }
}

/// Python reads a bool budget as the int 1 or 0; laya-rust follows.
fn budget(key: &str, v: &Value) -> BResult<i64> {
    match v {
        Value::Bool(b) => Ok(i64::from(*b)),
        Value::Number(n) => n
            .as_i64()
            .ok_or_else(|| bad(format!("{key} must be an integer"))),
        _ => Err(bad(format!("{key} must be an integer"))),
    }
}

fn count(key: &str, v: &Value) -> BResult<usize> {
    v.as_u64()
        .map(|n| n as usize)
        .ok_or_else(|| bad(format!("{key} must be a non-negative integer")))
}

/// Python's `batch_size`: any integer, with zero or negative meaning "no cap".
fn batch_size(v: &Value) -> BResult<Option<usize>> {
    v.as_i64()
        .map(|n| usize::try_from(n).ok().filter(|&n| n > 0))
        .ok_or_else(|| bad("batch_size must be an integer".to_string()))
}

fn string(key: &str, v: &Value) -> BResult<String> {
    v.as_str()
        .map(str::to_string)
        .ok_or_else(|| bad(format!("{key} must be a string")))
}

fn boolean(key: &str, v: &Value) -> BResult<bool> {
    v.as_bool()
        .ok_or_else(|| bad(format!("{key} must be TRUE or FALSE")))
}

pub fn predict_options(json: &str) -> BResult<PredictOptions> {
    let map = parse_object(json, &["min_confidence", "lang", "max_len", "head_max_len"], "predict")?;
    let mut o = PredictOptions::new();
    for (key, v) in &map {
        match key.as_str() {
            "min_confidence" => o.min_confidence = Some(min_confidence(v)?),
            "lang" => o.lang = Some(string(key, v)?),
            "max_len" => o.max_len = Some(budget(key, v)?),
            "head_max_len" => o.head_max_len = Some(budget(key, v)?),
            _ => unreachable!(),
        }
    }
    Ok(o)
}

pub fn batch_options(json: &str) -> BResult<BatchOptions> {
    let map = parse_object(
        json,
        &["batch_size", "sort_by_length", "min_confidence", "lang", "max_len", "head_max_len"],
        "batch",
    )?;
    let mut o = BatchOptions::new();
    for (key, v) in &map {
        match key.as_str() {
            "batch_size" => o.batch_size = batch_size(v)?,
            "sort_by_length" => o.sort_by_length = boolean(key, v)?,
            "min_confidence" => o.min_confidence = Some(min_confidence(v)?),
            "lang" => o.lang = Some(string(key, v)?),
            "max_len" => o.max_len = Some(budget(key, v)?),
            "head_max_len" => o.head_max_len = Some(budget(key, v)?),
            _ => unreachable!(),
        }
    }
    Ok(o)
}

pub fn long_options(json: &str) -> BResult<LongOptions> {
    let map = parse_object(json, &["window", "stride", "aggregate", "batch_size", "lang"], "long")?;
    let mut o = LongOptions::new();
    for (key, v) in &map {
        match key.as_str() {
            "window" => o.window = Some(count(key, v)?),
            "stride" => o.stride = Some(count(key, v)?),
            "aggregate" => o.aggregate = Some(string(key, v)?),
            "batch_size" => o.batch_size = batch_size(v)?,
            "lang" => o.lang = Some(string(key, v)?),
            _ => unreachable!(),
        }
    }
    Ok(o)
}

/// Engine construction options.
pub struct EngineOptions {
    pub intra_op_threads: Option<u32>,
    pub inter_op_threads: Option<u32>,
    pub lang_temperatures: LangTemperatureTable,
}

fn temperature_value(v: &Value) -> TemperatureValue {
    match v {
        Value::Number(n) if n.is_i64() => TemperatureValue::from(n.as_i64().unwrap()),
        Value::Number(n) => TemperatureValue::from(n.as_f64().unwrap_or(f64::NAN)),
        Value::Bool(b) => TemperatureValue::from(*b),
        Value::String(s) => TemperatureValue::from(s.as_str()),
        // laya replaces a value it cannot use with 1.0 and warns; mirror that path.
        _ => TemperatureValue::from(f64::NAN),
    }
}

/// `{lang: null | {temperature: [..] | null, temperature_by_options: {..} | null}}`, in order.
fn lang_temperatures(v: &Value) -> BResult<LangTemperatureTable> {
    let Value::Object(entries) = v else {
        return Err(bad("lang_temperatures must be an object keyed by language".into()));
    };
    let mut table = Vec::with_capacity(entries.len());
    for (lang, entry) in entries {
        let parsed = match entry {
            Value::Null => None,
            Value::Object(fields) => {
                let mut built = LangTemperature::new();
                for (key, value) in fields {
                    match (key.as_str(), value) {
                        (_, Value::Null) => {}
                        ("temperature", Value::Array(list)) => {
                            built = built.temperature(
                                list.iter().map(temperature_value).collect::<Vec<_>>(),
                            );
                        }
                        ("temperature_by_options", Value::Object(buckets)) => {
                            built = built.temperature_by_options(
                                buckets
                                    .iter()
                                    .map(|(k, v)| (k.clone(), temperature_value(v)))
                                    .collect::<Vec<_>>(),
                            );
                        }
                        _ => {
                            return Err(bad(format!(
                                "lang_temperatures['{lang}']: unexpected '{key}' (expected \
                                 temperature as a list, temperature_by_options as an object)"
                            )));
                        }
                    }
                }
                Some(built)
            }
            _ => {
                return Err(bad(format!(
                    "lang_temperatures['{lang}'] must be NULL or a list"
                )));
            }
        };
        table.push((lang.clone(), parsed));
    }
    Ok(table)
}

pub fn engine_options(json: &str) -> BResult<EngineOptions> {
    let map = parse_object(
        json,
        &["intra_op_threads", "inter_op_threads", "lang_temperatures"],
        "engine",
    )?;
    let threads = |key: &str| -> BResult<Option<u32>> {
        map.get(key)
            .map(|v| {
                v.as_u64()
                    .filter(|n| *n >= 1 && *n <= u32::MAX as u64)
                    .map(|n| n as u32)
                    .ok_or_else(|| bad(format!("{key} must be a positive integer")))
            })
            .transpose()
    };
    Ok(EngineOptions {
        intra_op_threads: threads("intra_op_threads")?,
        inter_op_threads: threads("inter_op_threads")?,
        lang_temperatures: match map.get("lang_temperatures") {
            Some(v) => lang_temperatures(v)?,
            None => Vec::new(),
        },
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_and_rejects() {
        let o = predict_options(r#"{"min_confidence": 0.7, "lang": "fr", "max_len": true, "head_max_len": null}"#).unwrap();
        assert_eq!(o.min_confidence, Some(MinConfidence::Scalar(0.7)));
        assert_eq!(o.lang.as_deref(), Some("fr"));
        assert_eq!(o.max_len, Some(1));
        assert_eq!(o.head_max_len, None);
        assert!(predict_options("").is_ok());
        assert!(predict_options("null").is_ok());
        assert_eq!(predict_options(r#"{"min_confidenc": 0.7}"#).err().unwrap().kind(), "bridge_invalid_option");

        let b = batch_options(r#"{"batch_size": 8, "sort_by_length": true, "min_confidence": {"choice:2": 0.6, "default": 0.5}}"#).unwrap();
        assert_eq!(b.batch_size, Some(8));
        assert!(b.sort_by_length);
        assert!(matches!(b.min_confidence, Some(MinConfidence::Map(ref m)) if m.len() == 2));
        assert_eq!(batch_options(r#"{"batch_size": -1}"#).unwrap().batch_size, None);
        assert_eq!(batch_options(r#"{"batch_size": 0}"#).unwrap().batch_size, None);
        assert!(batch_options(r#"{"batch_size": 1.5}"#).is_err());
        assert!(batch_options(r#"{"batch_size": true}"#).is_err());

        let l = long_options(r#"{"window": 512, "stride": 256, "aggregate": "auto"}"#).unwrap();
        assert_eq!((l.window, l.stride, l.aggregate.as_deref()), (Some(512), Some(256), Some("auto")));

        let e = engine_options(r#"{"intra_op_threads": 2, "lang_temperatures": {"fr": {"temperature": [1.1, 1, 0.9]}, "de": null}}"#).unwrap();
        assert_eq!(e.intra_op_threads, Some(2));
        assert_eq!(e.lang_temperatures.len(), 2);
        assert!(e.lang_temperatures[1].1.is_none());
        assert!(engine_options(r#"{"intra_op_threads": 0}"#).is_err());
    }
}
