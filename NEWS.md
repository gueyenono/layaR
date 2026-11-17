# layaR (development version)

First release, in preparation as 0.1.0. layaR runs Laya decision models
locally from R through the `laya-onnx` Rust crate and ONNX Runtime.

## Questions and predictions

* `laya_choice()`, `laya_score()` and `laya_noul()` build typed questions;
  `laya_questions()` combines them. `laya_preset()` gives the Python SDK's
  five presets (triage, email, guard, moderation, router).
* `laya_predict()` answers every question about a state in one forward pass;
  `laya_predict_batch()` does it for many states, in interruptible chunks
  with a progress bar; `laya_predict_long()` scans documents longer than the
  model's context.
* `laya_predict_batch()` sends one state per forward pass by default, which
  is fastest on a CPU (unlike the Python SDK, which batches a whole chunk).
  The `layaR.batch_size` option changes the default; `?layaR` lists all
  options.
* `min_confidence` reports, per answer, whether it passed an abstention
  threshold.
* Results print compactly and convert with `as.data.frame()` and
  `laya_probabilities()`; they keep the Python SDK's shape.
* `laya_annotate()` adds the answers to a data frame as columns: a factor for
  choice questions, the expected level for scores, P(true) for yes/no
  questions.
* Question sets read and write the Python SDK's JSON format
  (`as_laya_questions()`, `laya_questions_to_json()`).

## Models

* `laya_download_model()` downloads ONNX exports from Hugging Face
  (`gueyenono/laya-onnx` by default), resumably.
* `laya_import_model()` adds an export you made yourself;
  `laya_models()`, `laya_remove_model()` and `laya_model_root()` manage them.
  Exports in the cache shared with Laya's Rust and TypeScript SDKs are found
  too.
* `laya_engine()` loads a checkpoint (multilingual, English or
  typed-decisions); the prediction functions use `laya_default_engine()`.
  Engines refuse to run after `fork()` instead of hanging, and reconnect
  after `saveRDS()` or in PSOCK workers.

## Text utilities

* `laya_detect_language()`, `laya_clean_email()` and `laya_email_state()`,
  ported from the Python SDK. They need no model.

## Compatibility

* Results match the Python SDK on all 117 recorded cases for each of the
  English and multilingual checkpoints, and on all language and email
  probes.
* Errors have class `laya_error` and `laya_error_<kind>`.
* Linux and macOS. Windows is not supported yet.
