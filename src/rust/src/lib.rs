//! Phase 0 prototype bridge: load an engine, run one prediction, return JSON.
//! The production bridge (envelopes, classed errors, warnings, batch, long)
//! replaces this in Phase 2.

use extendr_api::prelude::*;
use laya::{Answer, LayaEngine, LayaResult, Question, QuestionSet};
use serde_json::{Map, Value, json};
use std::sync::Arc;

/// extendr 0.9's prelude does not export a one-parameter `Result`.
type Result<T> = std::result::Result<T, Error>;

/// An engine shared behind an Arc; held by R as an external pointer.
pub struct Engine(Arc<LayaEngine>);

impl std::fmt::Debug for Engine {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Engine")
    }
}

fn other<E: std::fmt::Display>(e: E) -> Error {
    Error::Other(e.to_string())
}

/// Load a Laya ONNX checkpoint directory.
/// @param model_dir Path to an exported checkpoint directory.
/// @noRd
#[extendr]
fn rs_engine_new(model_dir: &str) -> Result<ExternalPtr<Engine>> {
    let engine = LayaEngine::from_directory(model_dir).map_err(other)?;
    Ok(ExternalPtr::new(Engine(Arc::new(engine))))
}

/// Predict one state. Questions use the Python dict format.
/// @noRd
#[extendr]
fn rs_predict(engine: ExternalPtr<Engine>, state_json: &str, questions_json: &str) -> Result<String> {
    let state: Value = serde_json::from_str(state_json).map_err(other)?;
    let questions = parse_questions(questions_json)?;
    let result = engine.0.predict(state, &questions).map_err(other)?;
    Ok(encode_result(&result).to_string())
}

fn parse_questions(json: &str) -> Result<QuestionSet> {
    let value: Value = serde_json::from_str(json).map_err(other)?;
    let Value::Object(map) = value else {
        return Err(other("questions must be a JSON object keyed by question id"));
    };
    let mut set = QuestionSet::new();
    for (id, q) in map {
        let ins = q.get("instructions").cloned().unwrap_or(Value::String(String::new()));
        let crit = q.get("criteria").cloned().unwrap_or(Value::Null);
        let question = match q.get("type").and_then(Value::as_str) {
            Some("choice") => match crit {
                Value::Object(opts) => Question::choice(ins, opts),
                Value::Array(labels) => Question::choice_labels(
                    ins,
                    labels.into_iter().map(|l| match l {
                        Value::String(s) => s,
                        other => other.to_string(),
                    }),
                ),
                _ => return Err(other(format!("question {id}: choice criteria must be an object or array"))),
            }
            .map_err(other)?,
            Some("score") => match crit {
                Value::Array(levels) => Question::score(ins, levels).map_err(other)?,
                _ => return Err(other(format!("question {id}: score criteria must be an array"))),
            },
            Some("noul") => match crit {
                Value::Null => Question::noul(ins, Value::Null, Value::Null),
                Value::Object(mut m) => {
                    let f = m.remove("false").unwrap_or(Value::Null);
                    let t = m.remove("true").unwrap_or(Value::Null);
                    Question::noul(ins, f, t)
                }
                _ => return Err(other(format!("question {id}: noul criteria must be an object"))),
            },
            other_type => return Err(other(format!("question {id}: unknown type {other_type:?}"))),
        };
        set.insert(id, question).map_err(other)?;
    }
    Ok(set)
}

fn encode_result(result: &LayaResult) -> Value {
    let mut answers = Map::new();
    for (id, answer) in result.iter() {
        let mut a = Map::new();
        match answer {
            Answer::Choice(c) => {
                a.insert("type".into(), json!("choice"));
                a.insert("choice".into(), json!(c.choice));
                let probs: Map<String, Value> = c.probabilities.iter().map(|(k, v)| (k.clone(), json!(v))).collect();
                a.insert("probabilities".into(), Value::Object(probs));
            }
            Answer::Score(s) => {
                a.insert("type".into(), json!("score"));
                a.insert("score".into(), json!(s.score));
                a.insert("legend".into(), json!(s.legend));
                a.insert("probabilities".into(), json!(s.probabilities));
            }
            Answer::Noul(n) => {
                a.insert("type".into(), json!("noul"));
                a.insert("noul".into(), json!(n.probability));
            }
        }
        a.insert("confidence".into(), json!(answer.confidence()));
        a.insert("answer_confidence".into(), json!(answer.answer_confidence()));
        a.insert("action".into(), json!({ "act_probability": answer.action().act_probability }));
        answers.insert(id.to_string(), Value::Object(a));
    }
    let usage = result.usage();
    let mut u = Map::new();
    u.insert("input_tokens".into(), json!(usage.input_tokens));
    u.insert("output_tokens".into(), json!(usage.output_tokens));
    if let Some(s) = result.state_usage() {
        u.insert("state_tokens".into(), json!(s.state_tokens));
        u.insert("state_tokens_dropped".into(), json!(s.state_tokens_dropped));
        u.insert("truncated".into(), json!(s.truncated));
        u.insert("truncated_questions".into(), json!(s.truncated_questions));
    }
    json!({ "model": result.model(), "answers": answers, "usage": u })
}

// Macro to generate exports.
// This ensures exported functions are registered with R.
// See corresponding C code in `entrypoint.c`.
extendr_module! {
    mod laya_r;
    fn rs_engine_new;
    fn rs_predict;
}
