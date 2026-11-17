//! `LayaResult` -> Python-format result JSON (plan 6.4).
//!
//! The shape follows what laya-rust's own golden comparison (`tests/common/result_compare.rs`
//! and `tests/predict_long_tests.rs`) checks against Python's recorded output:
//!
//! - score `legend` and `probabilities` are objects keyed by level index (`{"0": ...}`);
//! - `low_confidence` is written only when true; `abstention` / `abstention_threshold` only when
//!   a `min_confidence` gate ran; `window` only for a `predict_long` scan;
//! - `usage` has `input_tokens` and `output_tokens`, plus, when the engine reports per-state
//!   diagnostics, `state_tokens`, `state_tokens_dropped`, `truncated` and `truncated_questions`;
//!   `options` only when some question's options collapsed; `windows` for a scan, where
//!   `truncated` is the count of truncated windows instead of a bool (when more than one window ran).

use laya::{Answer, LayaResult};
use serde_json::{Map, Value, json};

fn index_map<T: Clone + Into<Value>>(values: &[T]) -> Value {
    Value::Object(
        values
            .iter()
            .enumerate()
            .map(|(i, v)| (i.to_string(), v.clone().into()))
            .collect(),
    )
}

pub fn encode_answer(answer: &Answer) -> Value {
    let mut a = Map::new();
    match answer {
        Answer::Choice(c) => {
            a.insert("type".into(), "choice".into());
            a.insert("choice".into(), c.choice.clone().into());
            let probs: Map<String, Value> = c
                .probabilities
                .iter()
                .map(|(k, v)| (k.clone(), json!(v)))
                .collect();
            a.insert("probabilities".into(), Value::Object(probs));
        }
        Answer::Score(s) => {
            a.insert("type".into(), "score".into());
            a.insert("score".into(), json!(s.score));
            a.insert("legend".into(), index_map(&s.legend));
            a.insert("probabilities".into(), index_map(&s.probabilities));
        }
        Answer::Noul(n) => {
            a.insert("type".into(), "noul".into());
            a.insert("noul".into(), json!(n.probability));
        }
    }
    a.insert("confidence".into(), json!(answer.confidence()));
    a.insert("answer_confidence".into(), json!(answer.answer_confidence()));
    a.insert(
        "action".into(),
        json!({ "act_probability": answer.action().act_probability }),
    );
    if answer.low_confidence() {
        a.insert("low_confidence".into(), true.into());
    }
    if let Some(state) = answer.abstention() {
        a.insert("abstention".into(), state.into());
    }
    if let Some(threshold) = answer.abstention_threshold() {
        a.insert("abstention_threshold".into(), json!(threshold));
    }
    if let Some(w) = answer.window() {
        a.insert(
            "window".into(),
            json!({
                "index": w.index,
                "token_start": w.token_start,
                "token_end": w.token_end,
                "count": w.count,
            }),
        );
    }
    Value::Object(a)
}

pub fn encode_result(result: &LayaResult) -> Value {
    let mut answers = Map::new();
    for (id, answer) in result.iter() {
        answers.insert(id.to_string(), encode_answer(answer));
    }

    let usage = result.usage();
    let scan = result.scan_usage();
    let mut u = Map::new();
    u.insert("input_tokens".into(), json!(usage.input_tokens));
    u.insert("output_tokens".into(), json!(usage.output_tokens));
    if let Some(s) = result.state_usage() {
        u.insert("state_tokens".into(), json!(s.state_tokens));
        u.insert("state_tokens_dropped".into(), json!(s.state_tokens_dropped));
        match scan {
            // Python reports a count only when it actually slid windows; the one-pass fast path
            // (windows == 1) keeps the ordinary boolean.
            Some(scan) if scan.windows > 1 => {
                u.insert("truncated".into(), json!(scan.truncated_windows))
            }
            _ => u.insert("truncated".into(), json!(s.truncated)),
        };
        u.insert("truncated_questions".into(), json!(s.truncated_questions));
        if !s.options.is_empty() {
            let options: Map<String, Value> = s
                .options
                .iter()
                .map(|(id, o)| {
                    (
                        id.clone(),
                        json!({
                            "total": o.total,
                            "distinct": o.distinct,
                            "tokens_per_option": o.tokens_per_option,
                        }),
                    )
                })
                .collect();
            u.insert("options".into(), Value::Object(options));
        }
    }
    if let Some(scan) = scan {
        u.insert("windows".into(), json!(scan.windows));
    }

    json!({ "model": result.model(), "answers": answers, "usage": u })
}

#[cfg(test)]
mod tests {
    use super::*;
    use indexmap::IndexMap;
    use laya::{ActionInfo, ChoiceAnswer, NoulAnswer, ScoreAnswer, Usage};
    use std::collections::HashMap;

    #[test]
    fn encodes_python_shape() {
        let action = ActionInfo { act_probability: 1.0 };
        let mut probs = IndexMap::new();
        probs.insert("billing".to_string(), 0.8302);
        probs.insert("other".to_string(), 0.1698);
        let mut by_id = HashMap::new();
        by_id.insert(
            "dept".to_string(),
            Answer::Choice(ChoiceAnswer::new("billing", probs, 0.3427, 0.8302, action)),
        );
        by_id.insert(
            "urgency".to_string(),
            Answer::Score(ScoreAnswer::new(
                1.5,
                vec!["low".into(), "high".into()],
                vec![0.25, 0.75],
                0.19,
                0.75,
                action,
            )),
        );
        by_id.insert(
            "churn".to_string(),
            Answer::Noul(NoulAnswer::new(0.0097, 0.9903, 0.9903, action)),
        );
        let result = LayaResult::new(
            "laya-rl-agent",
            vec!["dept".into(), "urgency".into(), "churn".into()],
            by_id,
            Usage { input_tokens: 142, output_tokens: 0 },
        );
        let v = encode_result(&result);
        let ids: Vec<&String> = v["answers"].as_object().unwrap().keys().collect();
        assert_eq!(ids, ["dept", "urgency", "churn"]);
        assert_eq!(v["answers"]["dept"]["choice"], "billing");
        let labels: Vec<&String> = v["answers"]["dept"]["probabilities"]
            .as_object()
            .unwrap()
            .keys()
            .collect();
        assert_eq!(labels, ["billing", "other"]);
        assert_eq!(v["answers"]["urgency"]["legend"], json!({"0": "low", "1": "high"}));
        assert_eq!(v["answers"]["urgency"]["probabilities"], json!({"0": 0.25, "1": 0.75}));
        assert_eq!(v["answers"]["churn"]["noul"], json!(0.0097));
        // No gate ran and no scan: none of the optional keys appear.
        for key in ["low_confidence", "abstention", "abstention_threshold", "window"] {
            assert!(v["answers"]["churn"].get(key).is_none(), "{key}");
        }
        // No per-state diagnostics: only the token counts.
        assert_eq!(v["usage"], json!({"input_tokens": 142, "output_tokens": 0}));
        assert_eq!(v["model"], "laya-rl-agent");
    }
}
