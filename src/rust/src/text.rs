//! Text utilities that need no model: language detection and email cleaning (plan 7.8).
//!
//! Both are ports of the Python SDK's helpers (`laya.lang`, `laya.email`) and are checked
//! against Python-recorded probes in laya-rust's routing golden.

use crate::envelope::{BResult, BridgeError};
use laya::{LanguageAnalysis, LanguageDetection, LayaEmail};
use serde_json::{Map, Value, json};

/// One analysis as a JSON object. `script_profile` is sorted by share, largest first, so the
/// order is stable (upstream holds it in a `HashMap`).
fn encode_analysis(a: &LanguageAnalysis) -> Value {
    let mut profile: Vec<(&String, &f64)> = a.script_profile.iter().collect();
    profile.sort_by(|x, y| y.1.total_cmp(x.1).then_with(|| x.0.cmp(y.0)));
    let profile: Map<String, Value> = profile
        .into_iter()
        .map(|(k, v)| (k.clone(), json!(v)))
        .collect();
    json!({
        "script": a.script,
        "script_profile": profile,
        "language": a.language,
        "is_english": a.is_english,
        "language_undecided": a.language_undecided,
        "diacritic_rate": a.diacritic_rate,
        "non_latin_fraction": a.non_latin_fraction,
        "mixed_segment": a.mixed_segment,
    })
}

/// Analyse each state of a JSON array.
pub fn detect_languages(states_json: &str) -> BResult<Value> {
    let states: Value = serde_json::from_str(states_json)?;
    let states = states
        .as_array()
        .ok_or_else(|| BridgeError::new("bridge_json", "states must be a JSON array"))?;
    Ok(Value::Array(
        states
            .iter()
            .map(|s| encode_analysis(&LanguageDetection::analyse(s)))
            .collect(),
    ))
}

/// Clean each body of a JSON array of strings; `null` stays `null` (R's `NA`).
pub fn clean_emails(bodies_json: &str, max_chars: i64) -> BResult<Value> {
    let bodies: Value = serde_json::from_str(bodies_json)?;
    let bodies = bodies
        .as_array()
        .ok_or_else(|| BridgeError::new("bridge_json", "bodies must be a JSON array"))?;
    bodies
        .iter()
        .map(|b| match b {
            Value::Null => Ok(Value::Null),
            Value::String(s) => Ok(Value::String(LayaEmail::clean_body_signed(s, max_chars))),
            _ => Err(BridgeError::new("bridge_json", "each body must be a string or null")),
        })
        .collect::<BResult<Vec<Value>>>()
        .map(Value::Array)
}

/// Python's `email_state(subject, body, sender, clean, max_chars, **extra)`.
pub fn email_state(
    subject: &str,
    body: &str,
    sender: Option<&str>,
    clean: bool,
    max_chars: i64,
    extra_json: &str,
) -> BResult<Value> {
    let extra: Value = serde_json::from_str(extra_json)?;
    let extra = match extra {
        Value::Object(map) => map.into_iter().collect::<Vec<_>>(),
        _ => return Err(BridgeError::new("bridge_json", "extra fields must be a JSON object")),
    };
    Ok(LayaEmail::state_with_max_chars(
        subject, body, sender, clean, max_chars, extra,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_and_cleans() {
        let out = detect_languages(r#"["Please refund the duplicate charge", "मार्च का बिल"]"#).unwrap();
        assert_eq!(out[0]["is_english"], json!(true));
        assert_eq!(out[1]["script"], json!("devanagari"));
        let cleaned = clean_emails(r#"["Hi\n\n> quoted", null]"#, 3000).unwrap();
        assert_eq!(cleaned, json!(["Hi", null]));
        let state = email_state(" Locked ", "Body", None, true, 3000, r#"{"id": 3}"#).unwrap();
        assert_eq!(state, json!({"subject": "Locked", "body": "Body", "id": 3}));
    }
}
