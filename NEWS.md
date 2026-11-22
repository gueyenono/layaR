# layaR (development version)

# layaR 0.2.0

* layaR now loads ONNX Runtime when the first engine is created instead of
  building it in, using the `load-dynamic` feature that `laya-onnx` gained
  for layaR (NandhaKishorM/laya#1505).
  * New `laya_install_runtime()` downloads Microsoft's official ONNX Runtime
    1.28.0 build once (139 MB from its NuGet package, checked against the
    published SHA-512). `laya_download_model()` calls it when no runtime is
    installed, and the first engine offers to in interactive sessions.
  * New `laya_runtime_info()` shows which library is used. The
    `layaR.onnxruntime` option or the `ORT_DYLIB_PATH` environment variable
    selects a library of your own (ONNX Runtime 1.27 or newer).
  * New error kinds `runtime_not_found` and `runtime_load`.
* Windows (x64) is supported.
* Building from source no longer downloads anything or needs OpenSSL
  headers, so it works offline. The compiled package is about 14 MB instead
  of 50 MB.
* Intel Macs can install layaR, but Microsoft publishes no ONNX Runtime for
  them: predictions need a library you supply.

# layaR 0.1.1

* `laya_annotate()` gains `answer_confidence`, which adds an
  `<id>_answer_confidence` column: the confidence in the answer given (for a
  choice question, the chosen option's probability), the number
  `min_confidence` compares with its threshold.
* `laya_annotate()` explains that `state` takes column names as strings when
  given bare names (`state = c(subject, body)`), instead of failing with
  "object not found".
* New website article, "Using layaR with the tidyverse", showing the
  data-frame workflows with dplyr, tidyr, purrr and ggplot2.
* The README lists the supported platforms (Linux, and macOS on Apple
  silicon; Windows and Intel Macs are not supported yet) and how to install
  from r-universe.

# layaR 0.1.0

First release. layaR runs Laya decision models locally from R through the
`laya-onnx` Rust crate and ONNX Runtime.

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
