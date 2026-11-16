//! Python-format questions <-> `QuestionSet` (plan 6.3).
//!
//! The interchange format is Python's question dict, `{id: {type, instructions, criteria}}`,
//! with these forms (mirroring `Agent._validate_questions` / `_to_internal` in laya 0.4.34):
//!
//! | type     | criteria                                   | constructor                    |
//! |----------|--------------------------------------------|--------------------------------|
//! | `choice` | object `{label: description}`              | `Question::choice`             |
//! | `choice` | array of scalar labels                     | `Question::choice_labels`      |
//! | `score`  | non-empty array of levels, lowest first    | `Question::score`              |
//! | `noul`   | absent/null, or object keyed true/false    | `Question::noul`               |
//!
//! Python features the Rust engine has not ported (`labels` on noul, `option_order`) are refused
//! with a clear error instead of being ignored, since ignoring them would change the answers.

use crate::envelope::{BResult, BridgeError};
use laya::{Question, QuestionSet};
use serde_json::{Map, Value};
use std::collections::HashSet;

fn invalid(message: String) -> BridgeError {
    BridgeError::new("invalid_question", message)
}

/// A choice label as Python renders it with `str()`: strings as written, `True`/`False`,
/// integers in decimal, floats via `repr`-compatible formatting.
fn label_text(qid: &str, i: usize, label: &Value) -> BResult<String> {
    match label {
        Value::String(s) => Ok(s.clone()),
        Value::Bool(true) => Ok("True".into()),
        Value::Bool(false) => Ok("False".into()),
        Value::Number(n) if n.is_i64() || n.is_u64() => Ok(n.to_string()),
        Value::Number(n) => {
            let f = n.as_f64().unwrap_or(f64::NAN);
            // Python's repr of a whole float keeps ".0" (1.0), serde_json drops it.
            Ok(if f.fract() == 0.0 && f.is_finite() {
                format!("{f:.1}")
            } else {
                n.to_string()
            })
        }
        Value::Null => Err(invalid(format!(
            "question '{qid}': choice label {i} is null; a label is rendered as option text and \
             used as the answer key, so it must be a string, number or bool"
        ))),
        _ => Err(invalid(format!(
            "question '{qid}': choice label {i} must be a scalar (a string, number or bool)"
        ))),
    }
}

fn parse_one(qid: &str, def: &Value) -> BResult<Question> {
    let Value::Object(def) = def else {
        return Err(invalid(format!("question '{qid}' must be an object")));
    };
    for key in def.keys() {
        match key.as_str() {
            "type" | "instructions" | "criteria" => {}
            "labels" | "option_order" => {
                return Err(BridgeError::new(
                    "not_supported",
                    format!(
                        "question '{qid}': '{key}' is not supported by the Rust engine yet \
                         (laya-onnx has not ported it); remove it, or use the Python SDK"
                    ),
                ));
            }
            other => {
                return Err(invalid(format!(
                    "question '{qid}': unknown field '{other}' (expected type, instructions, criteria)"
                )));
            }
        }
    }
    let Some(ins) = def.get("instructions").cloned() else {
        return Err(invalid(format!("question '{qid}': 'instructions' is required")));
    };
    let crit = def.get("criteria").cloned().unwrap_or(Value::Null);
    let qtype = def.get("type").and_then(Value::as_str);
    let question = match qtype {
        Some("choice") => match crit {
            Value::Object(opts) => Question::choice(ins, opts)?,
            Value::Array(labels) => {
                let mut seen = HashSet::new();
                let mut texts = Vec::with_capacity(labels.len());
                for (i, label) in labels.iter().enumerate() {
                    let text = label_text(qid, i, label)?;
                    if !seen.insert(text.clone()) {
                        return Err(invalid(format!(
                            "question '{qid}': choice label {i} ('{text}') repeats an earlier label"
                        )));
                    }
                    texts.push(text);
                }
                Question::choice_labels(ins, texts)?
            }
            _ => {
                return Err(invalid(format!(
                    "question '{qid}': a choice question takes 'criteria' as an object \
                     {{label: description}} or an array of labels"
                )));
            }
        },
        Some("score") => match crit {
            Value::Array(levels) => {
                if let Some(i) = levels.iter().position(Value::is_null) {
                    return Err(invalid(format!(
                        "question '{qid}': score level {i} is null; give every level a description, \
                         index 0 first"
                    )));
                }
                Question::score(ins, levels)?
            }
            _ => {
                return Err(invalid(format!(
                    "question '{qid}': a score question takes 'criteria' as a list of level \
                     descriptions, index 0 first"
                )));
            }
        },
        Some("noul") => match crit {
            Value::Null => Question::noul(ins, Value::Null, Value::Null),
            Value::Object(map) => {
                let mut if_false = Value::Null;
                let mut if_true = Value::Null;
                for (key, value) in map {
                    match key.to_lowercase().as_str() {
                        "false" => if_false = value,
                        "true" => if_true = value,
                        _ => {
                            return Err(invalid(format!(
                                "question '{qid}': a noul question takes 'criteria' keyed only \
                                 'true'/'false' (either or both, and omitted is fine), got '{key}'"
                            )));
                        }
                    }
                }
                Question::noul(ins, if_false, if_true)
            }
            _ => {
                return Err(invalid(format!(
                    "question '{qid}': a noul question takes 'criteria' as an object with optional \
                     'true'/'false' descriptions, or omits it"
                )));
            }
        },
        Some(other) => {
            return Err(invalid(format!(
                "question '{qid}': unknown type '{other}' (expected choice, score or noul)"
            )));
        }
        None => {
            return Err(invalid(format!(
                "question '{qid}': 'type' is required (choice, score or noul)"
            )));
        }
    };
    Ok(question)
}

/// Parse a Python-format question object. Duplicate ids are refused, since a JSON parser would
/// otherwise keep the last one silently.
pub fn parse_questions(json: &str) -> BResult<QuestionSet> {
    let value: Value = serde_json::from_str(json)?;
    parse_questions_value(value)
}

pub fn parse_questions_value(value: Value) -> BResult<QuestionSet> {
    let Value::Object(map) = value else {
        return Err(invalid(
            "questions must be an object keyed by question id".to_string(),
        ));
    };
    let mut set = QuestionSet::new();
    for (id, def) in map.iter() {
        let question = parse_one(id, def)?;
        set.insert(id.clone(), question)?;
    }
    Ok(set)
}

/// Encode a `QuestionSet` back to the Python format (presets, validation round-trips).
pub fn encode_questions(set: &QuestionSet) -> Value {
    let mut out = Map::new();
    for (id, question) in set.iter() {
        let mut q = Map::new();
        match question {
            Question::Choice(c) => {
                q.insert("type".into(), "choice".into());
                q.insert("instructions".into(), c.instructions().clone());
                let crit: Map<String, Value> = c
                    .options()
                    .iter()
                    .map(|(label, desc)| (label.clone(), desc.clone()))
                    .collect();
                q.insert("criteria".into(), Value::Object(crit));
            }
            Question::Score(s) => {
                q.insert("type".into(), "score".into());
                q.insert("instructions".into(), s.instructions().clone());
                q.insert("criteria".into(), Value::Array(s.levels().to_vec()));
            }
            Question::Noul(n) => {
                q.insert("type".into(), "noul".into());
                q.insert("instructions".into(), n.instructions().clone());
                if !n.if_false().is_null() || !n.if_true().is_null() {
                    let mut crit = Map::new();
                    if !n.if_false().is_null() {
                        crit.insert("false".into(), n.if_false().clone());
                    }
                    if !n.if_true().is_null() {
                        crit.insert("true".into(), n.if_true().clone());
                    }
                    q.insert("criteria".into(), Value::Object(crit));
                }
            }
        }
        out.insert(id.to_string(), Value::Object(q));
    }
    Value::Object(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn kind_of(r: BResult<QuestionSet>) -> &'static str {
        r.err().expect("expected an error").kind()
    }

    #[test]
    fn all_forms_round_trip_in_order() {
        let input = json!({
            "dept": {"type": "choice", "instructions": "Which?", "criteria": {"billing": "refunds", "other": ""}},
            "labels_only": {"type": "choice", "instructions": "About?", "criteria": ["a", "b"]},
            "urgency": {"type": "score", "instructions": "How urgent?", "criteria": ["low", {"desc": "high"}]},
            "churn": {"type": "noul", "instructions": "Leaving?"},
            "phish": {"type": "noul", "instructions": "Phishing?", "criteria": {"True": "scam", "false": "legit"}}
        });
        let set = parse_questions_value(input).unwrap();
        assert_eq!(
            set.ids().collect::<Vec<_>>(),
            ["dept", "labels_only", "urgency", "churn", "phish"]
        );
        let out = encode_questions(&set);
        assert_eq!(out["dept"]["criteria"], json!({"billing": "refunds", "other": ""}));
        assert_eq!(out["labels_only"]["criteria"], json!({"a": null, "b": null}));
        assert_eq!(out["urgency"]["criteria"], json!(["low", {"desc": "high"}]));
        assert!(out["churn"].get("criteria").is_none());
        assert_eq!(out["phish"]["criteria"], json!({"false": "legit", "true": "scam"}));
        // The encoded form parses back to the same set.
        let again = encode_questions(&parse_questions_value(out.clone()).unwrap());
        assert_eq!(again, out);
    }

    #[test]
    fn scalar_labels_render_like_python_str() {
        let set = parse_questions_value(json!({
            "q": {"type": "choice", "instructions": "", "criteria": [1, 2.0, true, "x"]}
        }))
        .unwrap();
        let labels: Vec<&str> = set.get("q").unwrap().as_choice().unwrap().labels().collect();
        assert_eq!(labels, ["1", "2.0", "True", "x"]);
    }

    #[test]
    fn refusals() {
        let cases = [
            (json!([]), "invalid_question"),
            (json!({"q": {"type": "choice", "criteria": ["a"]}}), "invalid_question"),
            (json!({"q": {"instructions": "x"}}), "invalid_question"),
            (json!({"q": {"type": "maybe", "instructions": "x"}}), "invalid_question"),
            (json!({"q": {"type": "choice", "instructions": "x", "criteria": ["a", "a"]}}), "invalid_question"),
            (json!({"q": {"type": "choice", "instructions": "x", "criteria": [null]}}), "invalid_question"),
            (json!({"q": {"type": "choice", "instructions": "x", "criteria": []}}), "invalid_question"),
            (json!({"q": {"type": "score", "instructions": "x", "criteria": []}}), "invalid_question"),
            (json!({"q": {"type": "score", "instructions": "x", "criteria": ["a", null]}}), "invalid_question"),
            (json!({"q": {"type": "noul", "instructions": "x", "criteria": {"yes": "y"}}}), "invalid_question"),
            (json!({"q": {"type": "noul", "instructions": "x", "criteria": "nope"}}), "invalid_question"),
            (json!({"q": {"type": "noul", "instructions": "x", "extra": 1}}), "invalid_question"),
            (json!({"q": {"type": "noul", "instructions": "x", "labels": {"false": "B", "true": "A"}}}), "not_supported"),
            (json!({"q": {"type": "choice", "instructions": "x", "criteria": ["a", "b"], "option_order": [1, 0]}}), "not_supported"),
        ];
        for (input, kind) in cases {
            assert_eq!(kind_of(parse_questions_value(input.clone())), kind, "{input}");
        }
        assert_eq!(kind_of(parse_questions("{not json")), "bridge_json");
    }
}
