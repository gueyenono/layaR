# layaR — Implementation Plan

*Drafted 2026-11-15. Upstream reference: the `laya-rust` crate in `laya-repo/laya-rust`, published
on crates.io as `laya-onnx` 0.1.0 (imported as `laya`; built on `ort` 2.0.0-rc.13 and `tokenizers`
0.23; Rust edition 2024).*

---

## 1. Goal

Give R users local, in-process Laya inference: typed `choice` / `score` / `noul` decisions with
calibrated probabilities, run on ONNX Runtime through the Rust port, with no Python and no server.
The package should feel native to R: plain functions, lists and data frames, informative errors,
and a workflow that goes from "install" to "annotate a data frame of tickets" in a few lines.

### 1.1 In scope for v0.1

- Loading a checkpoint (multilingual, english, typed-decisions) from a local ONNX export.
- `predict`, `predict_batch` and `predict_long`, with the per-call options the Rust port supports
  (`min_confidence`, `lang`, `max_len`, `head_max_len`, window/stride/batch settings).
- Question constructors in R, plus import/export of the Python question format (JSON), so question
  sets can be shared between Python and R.
- The five built-in presets (`triage`, `email`, `guard`, `moderation`, `router`).
- Tidy results: printing, conversion to data frames, and a data-frame annotation helper.
- Model management: where models live, listing them, downloading them once they're published,
  importing an existing export.
- Pure-text utilities that need no model: language detection and email cleaning.
- CPU execution on Linux, macOS and Windows.

### 1.2 Out of scope for v0.1 (candidates for later)

| Feature | Why it's deferred |
|---|---|
| Router (multi-checkpoint routing) | Holds 2+ checkpoints of about 1.3 GB each; worth a separate design pass. Target v0.2. |
| Shortlist (embedding pre-filter) | Needs a callback into R for embeddings; target v0.2. |
| GPU (CUDA / DirectML) | Chosen at compile time in the crate; source-build-only for R. Target v0.3 and opt-in. |
| `vegaml`, images, audio, video, TileLang fast path | Python-only; not in the Rust port. |
| Prediction hooks, histogram-binning calibration, noul `labels` | Not ported to Rust yet (README, "Known gaps"). |
| Training / fine-tuning, MCP, `laya-serve` | Python-side tools. An `httr2` backend for `laya-serve` could come later behind the same R API. |

---

## 2. Upstream facts that shape the design

These were checked in `laya-repo/laya-rust` and drive the decisions in section 4.

1. **The API speaks JSON.** States, instructions, option descriptions and score levels are
   `serde_json::Value`, with `preserve_order` enabled so object key order is kept
   (`src/laya_engine.rs`, `src/questions.rs`). Passing JSON across the boundary therefore loses
   nothing.
2. **There's no JSON parser for questions.** `QuestionSet` is built in code with
   `Question::choice`, `choice_labels`, `score` and `noul` (`src/questions.rs:178-255`). The bridge
   has to translate the Python-style question dict itself.
3. **Answers don't derive `Serialize`** (`src/answers.rs`). Results have to be encoded by hand
   through the public accessors: `choice`, `probabilities`, `score`, `legend`, `probability`,
   `confidence()`, `answer_confidence()`, `action()`, `window()`, `abstention()` and so on.
4. **The golden vectors are ready-made parity fixtures.** Each file in `tests/golden/<checkpoint>/`
   contains the Python-format `questions`, the `state`, and Python's `result` (with `model`,
   `answers` and `usage`). That's 123 multilingual cases and 263 across the other checkpoints, about
   12 MB in total.
5. **The engine is `Send + Sync`**, holds a large ONNX session, and should be created once and
   reused (`src/laya_engine.rs`). Forward passes serialize on an internal mutex.
6. **There's one flat error enum, and the library never panics on bad input.** `LayaError` has
   variants `Io`, `Json`, `ArtifactsNotFound`, `DirectoryNotFound`, `MissingFile`, `Download`,
   `Tokenizer`, `Onnx`, `InvalidQuestion`, `InvalidConfig`, `CheckpointMismatch`, `NoMarkers`,
   `InvalidState`, `UnsupportedAggregate`, `InvalidWindow`, `NotSupported` and
   `InvalidMinConfidence` (`src/error.rs`).
7. **Warnings go through the `log` facade** at `warn` level with target `laya`, and no backend is
   linked. Unless we install a logger, they disappear.
8. **Model files.**
   - The fused layout is `model.onnx`, `model.onnx.data` (1.2–1.6 GB), `rl_agent_config.json` and
     `tokenizer/{tokenizer.json, tokenizer_config.json}`. The split layout (laya-ts) is also
     detected.
   - The exports **aren't on Hugging Face yet**. Today they come from `tools/export_onnx.py`, which
     needs Python and torch 2.9 or newer.
   - The crate's own download code fetches
     `https://huggingface.co/<repo>/resolve/main/<subfolder>/<file>`, using subfolder `""` for
     English (`src/model_artifacts.rs:452-600`).
   - Resolution order is `model_directory`, then `LAYA_ONNX_DIR`, `LAYA_ONNX_ROOT/<checkpoint>`, the
     cache, and finally an opt-in download.
9. **Build dependencies.**
   - `ort` with its default `download-binaries` feature fetches a prebuilt ONNX Runtime **at build
     time**.
   - `tokenizers` uses `onig`, which compiles C.
   - `ureq` and `rustls` are pulled in only by the crate's `download` feature, which is on by
     default.
   - Edition 2024 needs rustc 1.85 or newer.
10. **No async and no cancellation.** `predict` blocks the calling thread.

---

## 3. Architecture

```
 R user code         laya_predict(state, questions)   /   laya_annotate(df, questions, state = ...)
      │
      ▼
 R layer (R/)        argument checks · R → JSON (jsonlite) · S3 classes · chunking + progress
      │              + interrupts · classed conditions · model paths & downloads
      │   .Call (extendr wrappers): engine extptr + JSON strings in, envelope list out
      ▼
 Bridge crate        JSON → serde_json::Value / QuestionSet · LayaResult → JSON
 (src/rust)          LayaError → {kind, message} · log warnings → buffer · ExternalPtr<Engine>
      │
      ▼
 laya-onnx (crate)   tokenization · sequence building · batching · ONNX forward pass · calibration
      │
      ▼
 ONNX Runtime  +  model directory (~1.3 GB per checkpoint, in the user cache)
```

The bridge stays thin and has no logic of its own beyond translation. All inference behavior lives
upstream, and all R ergonomics live in R. That keeps upstream upgrades cheap: when `laya-onnx`
changes, only the translation layer moves.

---

## 4. Key design decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Cross the FFI boundary with JSON strings** for state, questions, options and results. | Upstream speaks `serde_json::Value` anyway. jsonlite and serde_json both handle UTF-8 and ordering correctly. It sidesteps extendr's `Robj` conversion corner cases, and it's trivially testable on both sides. The cost (microseconds) is negligible next to a forward pass (tens to hundreds of ms). `extendr`'s serde integration remains an optimization for later. |
| D2 | **The Python question dict is the interchange format**: `{id: {type, instructions, criteria}}`. | R users can paste question sets from Python docs, and the golden fixtures work unchanged. R constructors are sugar that produce this structure. |
| D3 | **Wrap the engine as an `ExternalPtr` inside an S3 object** that also records `model_dir`, the checkpoint and the options. | S3 is idiomatic and lightweight. Storing the path allows **automatic reconnection** after `saveRDS()`/`readRDS()` or a session restore, where the pointer becomes NULL. |
| D4 | **Every Rust entry point returns an envelope** `list(ok, value, error_kind, error_message, warnings)`. R raises the error. | It gives classed R conditions (`laya_error_no_markers`, and so on) without parsing message strings, and it never unwinds a Rust panic or R longjmp across the other language's stack frames. |
| D5 | **Buffer `log` warnings in Rust** (a small `log::Log` that appends to a thread-local `Vec<String>`) and return them in the envelope. R re-emits them with `cli::cli_warn()`. | Calling into R from inside a logger is unsafe if upstream ever logs from a worker thread. Buffering is always safe. |
| D6 | **Chunk large batches in R** and call Rust once per chunk. | Ctrl-C works between chunks, `cli` progress bars become possible, and memory stays bounded. Rust's `batch_size` still controls the forward-pass size inside each chunk. |
| D7 | **Download models from R, not Rust.** Build `laya-onnx` with `default-features = false`, which drops `ureq` and `rustls`. | R-side downloads (`curl::multi_download`) are resumable, interruptible and show progress, and the cache path follows CRAN policy (`tools::R_user_dir()`). Dropping the dependencies also shrinks the build. |
| D8 | **CPU only in v0.1.** | GPU support is a compile-time cargo feature and can't ship in prebuilt binaries. |
| D9 | **S3, not R6.** | Users don't mutate engine state. S3 gives `print`, `format`, `as.data.frame` and `predict` methods for free. |
| D10 | **Keep dependencies minimal.** Imports: `jsonlite`, `cli`. Suggests: `testthat (>= 3.0.0)`, `withr`, `curl`, `tibble`, `reticulate`, `knitr`, `rmarkdown`. | Fast installs and fewer CRAN failure points. `curl` is only needed for downloads, so it's checked with `rlang::check_installed`-style logic, or `requireNamespace` to avoid needing `rlang` at all. |
| D11 | **Put the state first, with a default engine**: `laya_predict(state, questions, engine = laya_default_engine())`. | It's pipe-friendly (`text \|> laya_predict(qs)`), and casual users never touch the engine. `laya_default_engine()` loads lazily and caches in a package environment keyed by checkpoint. |
| D12 | **License: Apache-2.0**, the same as upstream. | We statically link upstream code and redistribute its golden fixtures. Matching the license avoids compatibility questions. Vendored crate authors are listed in `inst/AUTHORS` (CRAN requirement). |

---

## 5. Package layout

The package root is the project directory, `layaR/`. `laya-repo/` stays git-ignored and goes into
`.Rbuildignore`; it's a reference checkout, not part of the package.

```
layaR/
├── DESCRIPTION              # SystemRequirements: Cargo (Rust's package manager), rustc >= 1.85
├── NAMESPACE                # roxygen-generated
├── LICENSE / LICENSE.md     # Apache-2.0
├── README.Rmd / README.md
├── NEWS.md
├── configure / configure.win  # rextendr-generated (Rust toolchain checks, Makevars from .in)
├── tools/
│   ├── msrv.R               # rextendr: checks rustc >= MSRV, prints versions to the install log
│   └── config.R
├── R/
│   ├── extendr-wrappers.R   # generated by rextendr::document(); never edited by hand
│   ├── engine.R             # laya_engine(), laya_default_engine(), print, reconnection
│   ├── questions.R          # laya_choice/score/noul(), laya_questions(), as_laya_questions()
│   ├── presets.R            # laya_preset()
│   ├── predict.R            # laya_predict(), laya_predict_batch(), laya_predict_long(), predict.laya_engine()
│   ├── results.R            # laya_result / laya_batch_result classes, print, as.data.frame
│   ├── annotate.R           # laya_annotate()
│   ├── models.R             # model root, listing, download, import
│   ├── text.R               # laya_detect_language(), laya_clean_email(), laya_email_state()
│   ├── json.R               # to_json()/from_json() with the package's exact jsonlite settings
│   ├── conditions.R         # envelope unwrapping, classed aborts, warning replay
│   ├── utils.R
│   └── zzz.R                # .onLoad: options defaults; package env for the engine cache
├── src/
│   ├── Makevars.in / Makevars.win.in   # rextendr templates (CARGO_BUILD_JOBS=2, offline vendoring)
│   ├── entrypoint.c
│   └── rust/
│       ├── Cargo.toml
│       ├── vendor-config.toml           # CRAN phase only
│       └── src/
│           ├── lib.rs        # extendr_module! { mod layaR; ... }
│           ├── engine.rs     # ExternalPtr<EngineHandle>, constructors, info
│           ├── predict.rs    # predict / batch / long entry points
│           ├── questions.rs  # Python-format JSON ⇄ QuestionSet
│           ├── results.rs    # LayaResult → serde_json::Value
│           ├── options.rs    # JSON → PredictOptions / BatchOptions / LongOptions / MinConfidence
│           ├── envelope.rs   # Result<Value> → R list; LayaError → kind slug
│           ├── logging.rs    # buffering log::Log implementation
│           └── text.rs       # language detection & email helpers
├── tests/
│   ├── testthat.R
│   └── testthat/
│       ├── helper-model.R    # skip_if_no_model(), cached test engine
│       ├── fixtures/golden/  # trimmed copies of upstream golden cases
│       ├── test-questions.R  # no model needed
│       ├── test-json.R       # no model needed
│       ├── test-results.R    # no model needed (canned result JSON)
│       ├── test-text.R       # no model needed
│       ├── test-predict.R    # model needed
│       └── test-parity.R     # model needed: R output vs Python golden results
├── data-raw/
│   └── make_fixtures.R       # trims laya-repo golden JSON → tests/testthat/fixtures/golden
├── vignettes/
│   ├── layaR.Rmd             # getting started
│   ├── questions.Rmd         # writing good questions
│   ├── data-frames.Rmd       # batch + laya_annotate
│   └── models.Rmd            # getting/exporting models, cache, threads, memory
└── inst/
    └── AUTHORS               # authors of vendored Rust crates (CRAN)
```

---

## 6. Rust bridge specification

### 6.1 `src/rust/Cargo.toml`

```toml
[package]
name = "layaR"
version = "0.1.0"
edition = "2024"
publish = false

[lib]
crate-type = ["staticlib"]
name = "layaR"

[dependencies]
extendr-api = "*"              # pin to the exact current release in Phase 0
laya-onnx = { version = "=0.1.0", default-features = false }   # no `download`: R downloads (D7)
serde_json = { version = "1", features = ["preserve_order", "float_roundtrip"] }
indexmap = "2"
log = "0.4"

[profile.release]
# Keep panic = "unwind" (the default) so extendr can turn a stray panic into an R error.
lto = "thin"
codegen-units = 1
```

- **Pinning.** Pin `laya-onnx` with `=`, and commit `Cargo.lock`. An upgrade is a deliberate step:
  bump the version, rerun the parity tests, and update NEWS.
- **Feature unification.** `laya-onnx` enables `ort`'s default features itself, so we **can't turn
  off** `download-binaries` from downstream. Section 9.4 covers why that matters for Windows and
  CRAN, and what the fix is.

### 6.2 Exported functions (internal; R users never call these directly)

All of these return the envelope from D4 unless noted. Names start with `rs_` so the generated
wrappers are clearly internal.

| Rust fn | Inputs | `value` on success |
|---|---|---|
| `rs_engine_new(model_dir, options_json)` | path; `{intra_op_threads, inter_op_threads, lang_temperatures}` | `ExternalPtr<EngineHandle>` |
| `rs_engine_info(engine)` | extptr | JSON: checkpoint, layout, model paths, `max_len`, `head_max_len`, config temperatures, language list in `lang_temperatures` |
| `rs_engine_close(engine)` | extptr | `NULL`; drops the session early and frees RAM |
| `rs_engine_is_live(engine)` | extptr | `TRUE`/`FALSE` (no envelope); `FALSE` after `readRDS` or `close` |
| `rs_predict(engine, state_json, questions_json, options_json)` | | result JSON |
| `rs_predict_batch(engine, states_json, questions_json, options_json)` | `states_json` is a JSON array | JSON array of results |
| `rs_predict_long(engine, state_json, questions_json, options_json)` | | result JSON (with `window` per answer and `scan_usage`) |
| `rs_questions_validate(questions_json)` | | normalized questions JSON (round-tripped through `QuestionSet`); exposes upstream validation **without a model** |
| `rs_preset(name, categories_json)` | `"triage" \| "email" \| "guard" \| "moderation" \| "router"` | questions JSON |
| `rs_bucket_keys()` | | character vector (no envelope) |
| `rs_artifacts_complete(dir)` | | `TRUE`/`FALSE` via `ModelArtifacts::is_complete` (no envelope) |
| `rs_detect_language(state_json)` | | JSON of `LanguageDetection::analyse` |
| `rs_email_clean_body(body, max_chars)` | | string |
| `rs_email_state(...)` | mapped to `LayaEmail::state` in Phase 5 | state JSON |
| `rs_versions()` | | named character vector: layaR bridge, laya-onnx, ort, ONNX Runtime API version (no envelope) |

`EngineHandle` is `struct EngineHandle { inner: Mutex<Option<Arc<LayaEngine>>> }`. The `Option`
lets `rs_engine_close` free the 1.3 GB session before R's garbage collector runs the finalizer.
Every call clones the `Arc` out under the lock and releases the lock before inference.

### 6.3 Question translation (`questions.rs`)

The input is the Python-format object. Its key order is the question order, and that order is
significant.

| `type` | `criteria` form | Rust constructor |
|---|---|---|
| `choice` | object `{label: description, ...}` (`""` or `null` means no description) | `Question::choice(instructions, [(label, desc), ...])` |
| `choice` | array of strings `[label, ...]` | `Question::choice_labels(instructions, labels)` |
| `score` | array of levels (strings or any JSON value), lowest first | `Question::score(instructions, levels)` |
| `noul` | absent or `null` | `Question::noul(instructions, Null, Null)` |
| `noul` | object `{"false": ..., "true": ...}` | `Question::noul(instructions, false_v, true_v)` |

Rules:

- `instructions` is any JSON value and defaults to `""`.
- An unknown `type` is an error.
- `labels` on a `noul` question is an **error that says it's not supported by the Rust engine
  yet**. Silently ignoring it would change answers relative to Python.
- Unknown keys raise an error naming the key. Strict beats silent here.
- Duplicate ids and labels are already refused upstream with `InvalidQuestion`. The JSON parse must
  detect duplicate object keys itself, because `serde_json` keeps the last value by default.
  Detect them with a custom `Visitor`, or by checking on the R side before encoding.
- **Before coding, verify the accepted forms against Python's normalizer** (`laya/agent.py` around
  line 1203 and `laya/onnx_agent.py` around line 292), and add any alias Python accepts.

The reverse direction (`QuestionSet` to JSON, needed for presets and `rs_questions_validate`) uses
the public accessors: `instructions()`, `options()`, `levels()`, `if_false()` and `if_true()`.

### 6.4 Result encoding (`results.rs`)

Match Python's output shape exactly, so golden `result` objects compare directly:

```json
{
  "model": "laya-rl-agent",
  "answers": {
    "department": {"type": "choice", "choice": "billing",
                   "probabilities": {"billing": 0.8302, "other": 0.1698},
                   "confidence": 0.3427, "answer_confidence": 0.8302,
                   "action": {"act_probability": 1.0}},
    "urgency":    {"type": "score", "score": 1.8974, "legend": ["not urgent", "soon", "blocking"],
                   "probabilities": [0.02, 0.06, 0.92], "...": "..."},
    "churn_risk": {"type": "noul", "noul": 0.0097, "...": "..."}
  },
  "usage": {"input_tokens": 142, "output_tokens": 0, "state_tokens": 32,
            "state_tokens_dropped": 0, "truncated": false, "truncated_questions": []}
}
```

Optional keys appear only when upstream reports them:

- `abstention`, `abstention_threshold`, `low_confidence` and `option_bucket` when `min_confidence`
  was given;
- `window` from `predict_long`;
- `scan_usage` (top level) from `predict_long`;
- per-option usage from `StateUsage::options`.

Two notes on the encoding:

- Emit floats with `serde_json`'s `float_roundtrip` so no precision is lost in transit.
- Confirm each key name against at least one golden file per feature (batch, long,
  `min_confidence`) in Phase 2.

### 6.5 Errors (`envelope.rs`)

Each `LayaError` variant maps to a snake_case `error_kind`: `io`, `json`, `artifacts_not_found`,
`directory_not_found`, `missing_file`, `download`, `tokenizer`, `onnx`, `invalid_question`,
`invalid_config`, `checkpoint_mismatch`, `no_markers`, `invalid_state`, `unsupported_aggregate`,
`invalid_window`, `not_supported` and `invalid_min_confidence`. Bridge-level failures (bad JSON from
R, a closed engine) get `bridge_*` kinds.

R raises `cli::cli_abort(message, class = c("laya_error_<kind>", "laya_error"))`. Users can then
write:

```r
tryCatch(laya_predict(x, qs), laya_error_no_markers = function(e) ...)
```

The upstream messages are already good (`NoMarkers` even suggests the fix), so R passes them
through and only adds context bullets, such as which state index failed in a batch.

### 6.6 Warnings (`logging.rs`)

- Install the logger once, from the first `rs_*` call, through `std::sync::Once` and
  `log::set_boxed_logger`. Set the max level to `Warn` and filter on target `laya`.
- The logger pushes `record.args().to_string()` into a `thread_local!` buffer.
- Every entry point drains the buffer into the envelope's `warnings`.
- R replays each warning with `cli::cli_warn(class = "laya_warning")`.

### 6.7 Threads, memory, signals

- ONNX Runtime threading is controlled through `intra_op_threads` and `inter_op_threads`. Expose
  both in R, with the R option `layaR.threads` as the default for intra-op threads.
- **Forked parallelism is unsafe** (`parallel::mclapply`, `future::multicore`): ONNX Runtime thread
  pools don't survive `fork()`. Document this. For PSOCK workers (`future::multisession`) the
  extptr isn't transferable, so each worker loads its own engine. Reconnection (D3) makes that
  automatic, but each worker uses about 1.3 GB of RAM, so document that too.
- Interrupts aren't possible inside a single forward pass. R-side chunking (D6) gives
  responsiveness between chunks.

---

## 7. R API specification

### 7.1 Engine

```r
laya_engine(
  checkpoint = c("multilingual", "english", "typed-decisions"),
  model_dir = NULL,            # overrides lookup; else laya_model_path(checkpoint)
  intra_op_threads = getOption("layaR.threads"),
  inter_op_threads = NULL,
  lang_temperatures = NULL     # named list, see 7.8
)
#> <laya_engine> multilingual · fused ONNX · max_len 1024 · head_max_len 256
#>   /home/me/.cache/R/layaR/onnx/multilingual

laya_default_engine(checkpoint = getOption("layaR.checkpoint", "multilingual"))  # cached, lazy
laya_engine_info(engine)      # list from rs_engine_info()
laya_engine_close(engine)     # free memory now
```

If the pointer is dead (after `readRDS`), any call reconnects from the stored `model_dir` and
options, with a one-time `cli_inform`.

### 7.2 Questions

```r
qs <- laya_questions(
  department = laya_choice(
    "Which department should handle this request?",
    billing   = "invoices, payments, refunds",
    technical = "bugs, outages, system errors",
    other     = "everything else"
  ),
  urgency    = laya_score("How urgent is this request?",
                          c("not urgent", "soon", "critical deadline or blocking issue")),
  churn_risk = laya_noul("Does the user threaten to cancel or leave?")
)
```

- `laya_choice(instructions, ..., .options = NULL)`. Named `...` or a named vector or list gives
  labels with descriptions. An unnamed character vector gives labels only.
- `laya_score(instructions, levels)` takes a character vector or a list of structured levels.
- `laya_noul(instructions, if_false = NULL, if_true = NULL)`.
- `laya_questions(...)` takes named questions. It checks for duplicate or empty ids and returns
  class `laya_questions`, a named list in Python format.
- `as_laya_questions(x)` accepts a list in Python format, a JSON string, or a path to a `.json`
  file. `laya_questions_to_json(qs, path = NULL, pretty = TRUE)` goes the other way.
- `c()`, `[` and `print` methods are provided. Print shows one line per question: id, type,
  options or levels, and the first 60 characters of the instructions.
- `laya_validate_questions(qs)` runs upstream validation through `rs_questions_validate` with no
  model needed. Prediction functions call it implicitly through Rust anyway.

### 7.3 Presets

```r
laya_preset("triage")                       # state field: message
laya_preset("email", categories = c(orders = "order status, shipping", returns = "returns"))
laya_preset_fields()                        # which state field each preset expects
```

### 7.4 Prediction

```r
laya_predict(state, questions, engine = laya_default_engine(), ...,
             min_confidence = NULL, lang = NULL, max_len = NULL, head_max_len = NULL)

laya_predict_batch(states, questions, engine = laya_default_engine(), ...,
                   batch_size = NULL, sort_by_length = FALSE,
                   min_confidence = NULL, lang = NULL, max_len = NULL, head_max_len = NULL,
                   chunk_size = 64L, progress = interactive())

laya_predict_long(state, questions, engine = laya_default_engine(), ...,
                  window = NULL, stride = NULL, batch_size = NULL, lang = NULL)

predict(engine, state, questions, ...)   # S3 method predict.laya_engine → laya_predict
```

- `state` is a character scalar, used verbatim, or a named list, which becomes an ordered JSON
  object.
- `states` is a character vector, a list of states, or a data frame where each row becomes an
  object.
- `questions` is a `laya_questions` object, or anything `as_laya_questions()` accepts.
- `min_confidence` is a scalar in [0, 1], or a named numeric vector whose names come from
  `laya_bucket_keys()` plus `"default"`.
- `...` must be empty (`rlang`-style check implemented in base R). That way a misspelled argument
  fails instead of being swallowed.

### 7.5 Results

`laya_result` is a list with `model`, `answers` (named list, one `laya_answer` per question) and
`usage`. `$`-access works naturally: `res$answers$department$choice`.

```r
res
#> <laya_result> laya-rl-agent · 3 answers · 142 input tokens
#>   department  choice  billing         p 0.91   confidence 0.34
#>   urgency     score   1.90 (0–2)                confidence 0.71
#>   churn_risk  noul    0.01 → FALSE              confidence 0.99

as.data.frame(res)        # one row per question:
#   id, type, answer (chr), value (dbl: chosen prob | score | P(true)),
#   confidence, answer_confidence, act_probability, abstention (if gated)
laya_probabilities(res)   # long: id, option, probability
laya_answer(res, "urgency")
```

`laya_batch_result` is a list of `laya_result`s. `as.data.frame()` on it stacks them with a
`state_id` column.

### 7.6 Data-frame helper

```r
tickets |>
  laya_annotate(qs, state = c("subject", "body"))   # each row → {"subject": ..., "body": ...}
#   + department (factor, levels = labels) + department_confidence
#   + urgency (dbl) + urgency_confidence
#   + churn_risk (dbl, P(true)) + churn_risk_confidence
```

- With one column, `state = "text"` passes the text verbatim.
- Options are `prefix = ""`, `confidence = TRUE`, `probabilities = FALSE` (adds a list-column) and
  `...` passed on to `laya_predict_batch()`.
- If `tibble` is installed and the input is a tibble, the output is a tibble too. Base R is used
  otherwise.

### 7.7 Models

```r
laya_model_root()                  # option layaR.model_root > env LAYA_ONNX_ROOT > R_user_dir(cache)/onnx
laya_model_path("multilingual")
laya_models()                      # data.frame: checkpoint, path, installed, layout, size_gb
laya_download_model("multilingual", repo = "convaiinnovations/laya", token = Sys.getenv("HF_TOKEN"))
laya_import_model("~/exports/onnx/multilingual", checkpoint = "multilingual", method = c("symlink", "copy"))
laya_export_model(...)             # optional, Phase 5: drives export_onnx.py via reticulate
```

- `laya_download_model()` asks before downloading in interactive sessions, since the files are
  about 1.3 GB. It fetches the five fused-layout files with `curl::multi_download()` (resumable,
  with progress) into a temporary directory, checks the result with `rs_artifacts_complete()`, and
  then moves it into place. If Hugging Face returns 404 (exports not published yet), it fails with
  a classed error explaining how to export and import a model.
- The engine also looks in the shared cross-SDK cache (`~/.cache/laya/onnx`) for reading, so a
  model exported for the Rust or TypeScript SDKs is reused. It never writes there.

### 7.8 Other utilities

```r
laya_detect_language("मार्च का बिल दो बार लिया गया")   # script, profile, English verdict
laya_clean_email(body, max_chars = 4000)              # strip quoted replies, signatures, disclaimers
laya_email_state(...)                                 # build an email state like the Python helper
laya_bucket_keys()                                    # valid min_confidence names
laya_versions()                                       # bridge / laya-onnx / ort versions
```

`lang_temperatures` takes this form in R:

```r
list(fr = list(temperature = c(1.1, 1.0, 0.9), temperature_by_options = c("choice:2" = 1.2)))
```

It's mapped to `LangTemperatureTable` in `options.rs`.

---

## 8. R ↔ JSON mapping rules (`R/json.R`)

One helper, `to_json()`, wraps `jsonlite::toJSON(x, auto_unbox = TRUE, digits = I(17),
always_decimal = TRUE, null = "null", na = "null", POSIXt = "ISO8601", Date = "ISO8601",
factor = "string")`. Every input goes through it.

The engine re-serializes a structured state the way Python's `json.dumps` does, and the model reads
that text, so R numbers follow Python's int/float split (changed in Phase 3 after the golden sweep
showed 1–3 token differences on numeric states).

| R value | JSON | Note |
|---|---|---|
| `"text"` (length 1) | `"text"` | A string state is used verbatim by upstream, not re-serialized. |
| named list | object, order kept | The common structured state. |
| unnamed list or vector of length > 1 | array | |
| length-1 vector inside a list | scalar | `auto_unbox`. **Gotcha:** a one-level `laya_score()` would collapse to a scalar, so constructors store criteria as lists, and `I()` is honored. |
| double | number, always with a decimal point, 17 significant digits | `149` → `149.0`, like a Python float. 17 digits reach Rust bit-for-bit, and Rust prints Python's shortest repr (`1/3` → `0.3333333333333333`). jsonlite's defaults (4 or 15 digits, `2` for `2.0`) changed the tokens. |
| integer `3L` | `3` | Like a Python int. Data read from CSV is usually integer already, as in pandas. A test pins both rules. |
| `NA` | `null` | Inside a state. In questions it's an error, raised in R. |
| `NULL` state | — | Error raised in R before the call. Upstream refuses null states too. |
| factor | string | |
| Date / POSIXct | ISO-8601 string | |
| data-frame row | object | Used by `laya_predict_batch()` and `laya_annotate()`. |
| non-UTF-8 string | converted with `enc2utf8()` | Tests cover Arabic, Hindi and CJK. |

Results come back with `jsonlite::fromJSON(x, simplifyVector = FALSE)`, which preserves order and
types, and are then shaped into S3 objects in R.

---

## 9. Build, CI and distribution

### 9.1 Local development notes (this machine)

- **Toolchain.** R 4.6.0, rustc and cargo 1.95.0 (both from Nix), rextendr 0.5.0, devtools 2.5.2,
  usethis 3.2.1, testthat 3.3.2 and jsonlite 2.0.0 are already installed.
- **Working location (decision 6).** Develop in the current folder,
  `/home/gueyenono/Drives/My_Drive/projects/r_packages/layaR`, which is a local disk. `laya-repo/`
  stays there as the reference checkout used for fixture generation. `src/rust/target/` (several
  GB with `ort` and `tokenizers`) is git-ignored and kept out of builds.
- **Git ownership.** The folder is owned by `root` with mode 777, and git already refuses to work
  in `laya-repo` ("dubious ownership"). The same will happen after `git init` on the package. Fix
  it once with `git config --global --add safe.directory <path>`, or change the folder's ownership
  to your user.
- **Exported models.** Store them outside the package tree (for example in
  `tools::R_user_dir("layaR", "cache")/onnx`), since they're 1.3–1.6 GB each and `R CMD build`
  would otherwise try to bundle them.
- **Nix.** `ort`'s prebuilt ONNX Runtime downloads during the build. Check in Phase 0 whether the
  binary links statically (no runtime `.so` lookup) on this Nix setup. If it's dynamic, it may need
  `LD_LIBRARY_PATH` or `patchelf` on NixOS-style environments.
- **Model for testing.** Export `multilingual` (and later `english`) once with
  `python laya-rust/tools/export_onnx.py --model multilingual` in a throwaway venv, and set
  `LAYAR_TEST_MODEL_ROOT` for the tests.

### 9.2 CI (GitHub Actions)

- `R-CMD-check` uses `r-lib/actions` with a matrix of ubuntu (release, devel, oldrel-1), macOS
  (arm64) and Windows (release), plus `dtolnay/rust-toolchain@stable` and `Swatinem/rust-cache` for
  cargo. Model-free tests run everywhere.
- `parity` is a scheduled and manual job on Linux only. It restores the exported model from
  `actions/cache`, or from a private release asset or Hugging Face repo you control (re-hosting
  needs the license check in section 12), and runs `test-parity.R` with
  `LAYAR_TEST_MODEL_ROOT` set.
- `rust` runs `cargo fmt --check`, `cargo clippy -D warnings` and `cargo test` on the bridge crate.
  Unit tests cover JSON translation without a model.
- `pkgdown` deploys the docs site.

### 9.3 r-universe (first distribution target)

r-universe builds Rust packages and ships binaries for Windows, macOS and Linux, so users don't
need Rust installed. Setup: create a `<you>.r-universe.dev` registry repo with `packages.json`
pointing to the layaR GitHub repo. **Verify in Phase 0** that r-universe builders allow the network
access `ort`'s `download-binaries` needs at build time. If they don't, the CRAN strategy in 9.4 is
needed for r-universe too.

### 9.4 The Windows and CRAN problem, and the fix

- **Windows.** R builds packages with the GNU toolchain (Rtools, target `x86_64-pc-windows-gnu`).
  `ort`'s prebuilt ONNX Runtime binaries target MSVC, so expect `download-binaries` to fail or
  mis-link there. **Test this first in Phase 0.**
- **CRAN.** CRAN forbids downloads during builds, requires vendored crates (`cargo build
  --offline`), and limits `cargo` to 2 jobs.
- **The fix in both cases is `ort`'s `load-dynamic` feature.** The package then loads the ONNX
  Runtime shared library at runtime, and a function `laya_install_runtime()` downloads Microsoft's
  official ONNX Runtime release into `tools::R_user_dir("layaR", "data")` on first use. This is
  the same pattern the CRAN `torch` package uses for libtorch.
- **The blocker:** `laya-onnx` turns on `ort`'s default features, so we can't switch them off from
  downstream. Options, in order of preference:
  1. Upstream adds a `load-dynamic` feature to `laya-onnx` and makes `ort/download-binaries` part
     of `default` (section 11, ask U2, raised as an issue per decision 5). This is a small, clean
     change that benefits every binding.
  2. If upstream doesn't adopt it: a `[patch.crates-io]` pointing at our own fork with that change.
  3. Vendoring a patched copy of `laya-onnx` inside `src/rust/` (last resort; Apache-2.0 allows
     it, with attribution).
- **Other CRAN checklist items:**
  - `rextendr::vendor_pkgs()`, then `vendor.tar.xz`.
  - `rextendr::write_license_note()`, then `inst/AUTHORS`.
  - `SystemRequirements` and the MSRV check in `tools/msrv.R`.
  - Print `rustc --version` in the install log.
  - Examples and tests skip without a model.
  - Watch the tarball size: `tokenizers`, `ort`, `regex` and `onig` vendored may exceed CRAN's
    5 MB guideline, which needs justification in `cran-comments.md`.

---

## 10. Phased roadmap

Estimates are in focused working days and are rough.

### Phase 0 — Feasibility spike (2–3 days)

Goal: prove the toolchain end to end before designing anything.

1. Export the `multilingual` ONNX model locally (Python venv, `export_onnx.py`). Note the size and
   the RAM used while loading.
2. Create a throwaway binary crate depending on `laya-onnx = { version = "=0.1.0",
   default-features = false }` that loads the model and runs the README quickstart. Record:
   - build time and `target/` size;
   - the resulting binary size;
   - whether ONNX Runtime links statically;
   - CPU latency per `predict`.
3. Create a minimal extendr package in a scratch location with one function, `rs_predict(dir,
   state_json, questions_json)` returning a JSON string, and call it from R.
4. Push the scratch package to GitHub and run a Windows `R CMD INSTALL` in Actions to settle the
   `download-binaries` question on the GNU target. Do the same on macOS arm64.
5. Pin `extendr-api` and confirm the `ExternalPtr` API for the pinned version.
6. **Model license check (decision 3). Done 2026-11-15.**
   - All three checkpoints are **Apache-2.0** (model-card metadata and footer), and the cards
     state no extra restrictions.
   - Backbones: ModernBERT-large is Apache-2.0 (English and typed-decisions); mmBERT-base is
     **MIT** (multilingual).
   - So re-hosting ONNX conversions is permitted, provided we:
     - ship the Apache-2.0 license text;
     - keep the copyright and attribution notices (Convai Innovations; the MIT notice for
       mmBERT-base);
     - state that the files are ONNX conversions made with `export_onnx.py`;
     - include the citation block from the `laya` card. ModernBERT and mmBERT also ask for
       citations.
   - No repo ships ONNX files today, so re-hosted files would be a new artifact.
7. **Upstream issues (decision 5).** Open issues U1 (publish ONNX exports) and U2
   (`load-dynamic`). U2 is the one that matters most for Windows and CRAN.

**Done when** R prints a correct `choice` answer on Linux, and the Windows and macOS outcomes are
known. **Decision point:** if Windows fails, start the upstream `load-dynamic` ask (U2) immediately
and plan to ship Linux and macOS first.

### Phase 1 — Package skeleton (0.5 day)

Create the package in the current folder (decision 6) with `usethis::create_package(".")`, then:

- `use_apache_license()`
- `rextendr::use_extendr()`
- `use_testthat(3)`
- `use_readme_rmd()`
- `use_news_md()`
- `use_github_action("check-standard")`
- `use_pkgdown()`

Then `git init` (after the `safe.directory` fix in 9.1), create the GitHub repo, set
`.Rbuildignore` (`laya-repo`, `plan`, `data-raw`) and set `.gitignore` (`laya-repo/`,
`src/rust/target`, `*.so`, `src/rust/vendor`).

**Done when** `devtools::check()` passes on the hello-world template.

### Phase 2 — Rust bridge (4–6 days)

1. `envelope.rs` and `logging.rs` first, since everything depends on them.
2. `questions.rs`: JSON to `QuestionSet` and back, with unit tests on every form in 6.3 and every
   error, including duplicate keys.
3. `results.rs`: `LayaResult` to JSON, with unit tests that build answers with the public `new()`
   constructors.
4. `options.rs`: `PredictOptions`, `BatchOptions`, `LongOptions`, `MinConfidence` and
   `lang_temperatures`.
5. `engine.rs` and `predict.rs`: the extptr handle and the three predict entry points.
6. `rs_preset`, `rs_bucket_keys`, `rs_artifacts_complete` and `rs_versions`.
7. `cargo clippy` and `cargo test` run clean. `rextendr::document()` generates the wrappers.

**Done when** each `rs_*` function can be called from R and returns the envelope, and the bridge
unit tests pass.

### Phase 3 — R core API (4–6 days)

1. `json.R` and `conditions.R`, with envelope unwrapping, classed errors and warning replay.
2. `questions.R` and `presets.R`, with constructors, validation, JSON import/export and print
   methods.
3. `engine.R`: `laya_engine()`, the default-engine cache, reconnection after `readRDS`, `close`
   and print.
4. `predict.R`: the three predict functions, chunking with `cli` progress, the `...` check, and
   `predict.laya_engine`.
5. `results.R`: classes, print and format, `as.data.frame`, `laya_probabilities` and
   `laya_answer`.
6. roxygen documentation for every exported function, with examples guarded by
   `if (laya_model_available())`.

**Done when** the README quickstart runs end to end in R, and model-free tests pass on all three
operating systems in CI.

### Phase 4 — Parity and robustness (3–4 days)

1. Write `data-raw/make_fixtures.R`. It reads `laya-repo/laya-rust/tests/golden/*/case_*.json` and
   keeps `name`, `state`, `questions`, the batch or long options, and `result` (or the expected
   error), dropping `input_ids` and `logits`. It writes about 30 representative cases per
   checkpoint, under 1 MB in total.
2. `test-parity.R`: for each fixture, the R output matches Python's `result` (probabilities within
   1e-4, since upstream rounds to 4 decimal places; exact match for labels and keys), and expected
   errors produce the right `laya_error_*` class.
3. Edge cases:
   - empty questions;
   - empty batch;
   - `NULL`/`NA` states;
   - very long states (truncation flags in `usage`);
   - `NoMarkers`;
   - non-ASCII ids and labels (the Arabic case);
   - structured criteria;
   - a whole-number double in a state.
4. Lifecycle tests: `saveRDS`, then `readRDS`, then a prediction that reconnects; `close` followed
   by a call raises a clear error; `gc()` doesn't crash.
5. Fork-safety documentation and test: a deliberately skipped test, plus a clear message.

**Done when** parity is green for the multilingual and english fixtures.

**Status (2026-11-16).**
- `data-raw/make_fixtures.R` keeps all 117 non-shortlist cases per checkpoint: about 1 MB of JSON
  each, 57 KB gzipped. That is more than the planned 30, but compressed it is small, and the full
  set is the real parity check.
- 50 cases per checkpoint are marked `core` (30 chosen, plus every error case) and run by default
  (about 3 minutes per checkpoint). `LAYAR_PARITY=all` runs everything. The tests skip on CRAN and
  without a model.
- Python's `ValueError`/`TypeError` are mapped to layaR kinds from the message, and the test
  checks the class. All 20 error cases match. `long_no_state_room` is `invalid_window`.
- Fork safety is enforced, not only documented: engines record the PID that loaded them, and
  using one in a forked child raises `laya_error_forked` before any Rust code runs. A real
  `mcparallel()` test covers this.
- The english model was exported for this phase.

### Phase 5 — Models, data frames and text utilities (2–3 days)

1. `models.R`: root resolution, `laya_models()`, `laya_download_model()`, `laya_import_model()`,
   and a clear "no model yet" error with next steps.
   - **Re-hosting (decision 3):** if the Phase 0 license check allows it, export all three
     checkpoints, upload them in the fused layout to a Hugging Face repo you control (with the
     original model-card attribution and license), and make that repo `laya_download_model()`'s
     default `repo`. Switch the default to upstream once it publishes.
2. `annotate.R`: `laya_annotate()`, with factor columns for choice questions and tibble
   preservation.
3. `text.R`: language detection, email cleaning and the email state.
4. Optional: `laya_export_model()` through reticulate. It installs the exporter's Python
   dependencies into a dedicated virtualenv and runs `export_onnx.py`. The script isn't in the
   PyPI wheel, so either fetch it at a pinned commit or ship it in `inst/python/` with attribution.

**Status (2026-11-16, branch `phase5-models`).**
- `models.R`: `laya_models()`, `laya_download_model()`, `laya_import_model()` (symlink or copy)
  and `laya_remove_model()`. Downloads mirror laya-rust: the fused layout is probed first, then
  split, under upstream's repo layout (english at the root). They use resumable
  `curl::multi_download()` into a staging folder that is moved into place only once complete, and
  `HF_ENDPOINT` and `HF_TOKEN` are honoured. While nothing is published, the real upstream repo
  gives `laya_error_model_not_published` with export and import steps. The shared cross-SDK cache
  (`~/.cache/laya/onnx`) is read but never written; `options(layaR.shared_cache = FALSE)` turns
  it off. Tests run offline against a fake repo over `file://`.
- `annotate.R`: `laya_annotate()`. Choice questions give factors (levels are the options), score
  questions give the expected level, and noul questions give P(true). It adds `_confidence`, and
  `_abstained` when gated, plus an optional `_probabilities` list-column. Rows whose state is all
  `NA` get `NA` answers, and tibbles stay tibbles.
- `text.R`: `laya_detect_language()`, `laya_clean_email()` and `laya_email_state()` (with
  Python's `sender` argument name), through new bridge functions. They match Python on all 261
  language probes and all 275 email probes from laya-rust's routing golden, which are now
  fixtures.
- Not done yet: re-hosting the exports (needs a Hugging Face account and the user's go-ahead),
  and the optional `laya_export_model()`.

### Phase 6 — Documentation, performance and release 0.1.0 (3–5 days)

1. Vignettes: getting started, writing questions (option order, head budget, `NoMarkers`), data
   frames and batches, models and performance (threads, memory, forking).
2. Benchmarks with `bench::mark`:
   - `laya_predict` overhead against the raw Rust call, to confirm the JSON boundary is
     negligible;
   - batch throughput for different values of `chunk_size` and `batch_size`;
   - the effect of the thread count.
3. A pkgdown site, the README with a demo GIF, and NEWS.
4. Tag v0.1.0 and publish on r-universe.

### Phase 7 — CRAN (5–10 days; after the upstream `load-dynamic` change)

`load-dynamic` with `laya_install_runtime()`, vendoring, offline builds, `inst/AUTHORS`, size
justification, examples and tests that run without a model, `rhub` and win-builder checks, then
`cran-comments.md` and submission.

### Later (v0.2+)

- `laya_router()`, using `LayaRouter` with `max_loaded` and preload and an LRU over checkpoints.
- Shortlist support with an R embedding callback, which has to run on R's main thread.
- GPU builds from source (`LAYAR_FEATURES=cuda`).
- An `httr2` backend for `laya-serve` behind the same `laya_predict()` generic, for features that
  only exist in Python.
- `extendr` serde integration in place of JSON strings, if profiling ever shows the boundary
  matters.

---

## 10a. Phase 0 findings (2026-11-16)

**Model export** (multilingual, CPU, `--verify`)
- Took 2 min, with a peak of 6.6 GB of RAM.
- Output: `~/.cache/R/layaR/onnx/multilingual`, 1.3 GB.
- Verification passed: max logit difference against PyTorch was 4.8e-6 across 36 shape
  combinations.

**Dependency**
- `laya-onnx` is **not on crates.io**, despite its README. It's pinned through git to commit
  `80a1da1` (release 0.4.34).
- `ort` is pinned to `=2.0.0-rc.13`. Without the pin, Cargo picks rc.15, unlike upstream's
  lockfile.

**Linking (Linux)**
- `download-binaries` fetches a **static** `libonnxruntime.a`, so there's no runtime `.so` to
  locate.
- `layaR.so` is 121 MB, and `target/` is 885 MB.
- The link needs `-Wl,-z,noexecstack`, because one ONNX Runtime assembly object lacks
  `.note.GNU-stack` and glibc refuses an executable-stack `.so`.

**OpenSSL at build time**
- `ort-sys`'s download uses `ureq` with native TLS, so Linux builds need OpenSSL headers
  (`libssl-dev`). Add it to `SystemRequirements`.
- On this Nix machine, set `OPENSSL_LIB_DIR`, `OPENSSL_INCLUDE_DIR` and `LD_LIBRARY_PATH` to a
  Nix OpenSSL. A dev `.envrc` or a note in `CONTRIBUTING` should cover this.

**rextendr 0.5.0 output needed two fixes**
- The init routine name was wrong for the mixed-case package name.
- The `configure` shebang was the local Nix path for `sh`.

**Prototype results**
- R's output is **identical** to Python's golden result on `case_arabic`.
- Engine load takes 6.7 s, `predict` about 290 ms on CPU, and the R process uses about 1.0 GB
  of RAM.
- A missing model directory gives a clean R error.

**CI on the prototype (PR #1)**
- All three Ubuntu builds pass, with ONNX Runtime included.
- macOS initially failed because Apple's `ld` has no `-z`. `-z noexecstack` is now substituted
  on Linux only, through `tools/config.R`.
- **Windows is confirmed blocked:** `ort-sys@2.0.0-rc.13: no prebuilt binaries available for
  target x86_64-pc-windows-gnu`. Upstream ask U2, or our own fork with `load-dynamic`, is
  required for Windows.

**extendr 0.9 API notes**
- The prelude has no one-parameter `Result`; define a local alias.
- `ExternalPtr<T>` needs `T: Debug`, and `LayaEngine` doesn't implement it, so wrap it in a
  newtype with a manual `Debug`.
- `IndexMap` isn't `Serialize` without indexmap's `serde` feature, so encode it by hand.

## 11. Upstream asks (NandhaKishorM/laya)

Each of these makes layaR simpler and helps every other binding. Per decision 5, raise them as
**issues only**: describe the problem, the proposed change, and why it helps all bindings. layaR
must not block on any of them. Every ask has a workaround on our side.

| # | Ask | Impact on layaR |
|---|---|---|
| U1 | Publish the ONNX exports on Hugging Face (already planned in `MODELS.md` §6). | Removes the Python and torch export step, the biggest UX hurdle. |
| U2 | Pass `ort`'s features through: a `load-dynamic` feature, with `download-binaries` in `default`. | Unblocks Windows GNU and CRAN (section 9.4). |
| U3 | An optional `serde` feature: `Serialize` on `LayaResult` and `Answer`, `Deserialize` for `QuestionSet` from the Python dict format. | Removes most of `questions.rs` and `results.rs`. Upstream also owns the format, so drift is impossible. |
| U4 | Port noul `labels`, prediction hooks and histogram calibration. | Feature parity with Python. |
| U5 | Expose token counting (`LayaEngine::tokenizer()` or a `count_tokens`). | Enables an R helper that budgets state length before prediction. |

---

## 12. Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| ONNX exports never published on Hugging Face | Medium | High (setup needs Python) | `laya_import_model()` plus an optional reticulate export helper; re-host exports yourself **after checking the checkpoints' licenses on their Hugging Face model cards**. |
| `ort` prebuilt binaries fail on Windows GNU | High | High (no Windows) | Test in Phase 0; U2 or a patched fork with `load-dynamic`; ship Linux and macOS first. |
| `laya-onnx` 0.1.0 changes API or behavior | Medium | Medium | Exact pin plus `Cargo.lock`; parity suite gates upgrades; the thin bridge keeps upgrades cheap. |
| `ort` is still a 2.0 release candidate | Medium | Medium | Exact pin through `Cargo.lock`; upgrade only alongside `laya-onnx`. |
| Memory (about 1.3–1.6 GB per engine) surprises users | High | Medium | Document it; one cached default engine; `laya_engine_close()`; warn when a second checkpoint loads. |
| jsonlite encoding subtly changes states (digits, unboxing) | Medium | High (wrong answers) | A single `to_json()` helper; `digits = NA`; criteria stored as lists; parity and JSON unit tests. |
| Rust build size and time annoy source installers | High | Low | Binaries through r-universe; `CARGO_TARGET_DIR` guidance; `lto = "thin"`. |
| CRAN rejects tarball size | Medium | Medium | Justify in cran-comments; stay on r-universe if CRAN refuses. |
| Fork-based parallelism crashes R | Medium | Medium | Document it; detect a forked child (PID change since load) and refuse with a clear error. |

---

## 13. Decisions (resolved 2026-11-15)

| # | Question | Decision | Effect on the plan |
|---|---|---|---|
| 1 | License | **Apache-2.0**, matching upstream | D12 confirmed. `usethis::use_apache_license()` in Phase 1. |
| 2 | Argument order | **State first, with a default engine** | D11 confirmed: `laya_predict(state, questions, engine = laya_default_engine())`. |
| 3 | Model hosting | **Re-host the exports if the license allows** | New tasks: check the checkpoint licenses on the Hugging Face model cards (Phase 0); if redistribution is allowed, publish the exports to a Hugging Face repo you control and make it `laya_download_model()`'s default `repo` until upstream publishes (Phase 5). |
| 4 | Distribution | **r-universe first**; CRAN later | Phases 0–6 target r-universe. Phase 7 (CRAN) waits until `load-dynamic` is available. |
| 5 | Upstream | **Issues only**, no PRs | Section 11 asks go in as issues. If U2 isn't adopted, the fallback is a patched fork through `[patch.crates-io]`, or a vendored copy (section 9.4). layaR keeps its own translation code (U3 is a nice-to-have). |
| 6 | Dev location | **The current folder** (`/home/gueyenono/Drives/My_Drive/projects/r_packages/layaR`). It's a local disk, not a synced Google Drive folder. | The package is created in place. `laya-repo/` stays alongside as the reference checkout, ignored by git and by `R CMD build`. See 9.1 and Phase 1. |
| 7 | Windows (2026-11-16) | **Linux and macOS first.** No fork for now. | Windows is commented out of the CI matrix. U2 is posted as NandhaKishorM/laya#1505. Windows support resumes when upstream exposes `load-dynamic`, or if we decide to fork later. |
