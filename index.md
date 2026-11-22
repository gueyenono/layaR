# layaR

layaR runs [Laya](https://github.com/NandhaKishorM/laya) decision models
locally from R. You ask typed questions about a piece of text or a
record (pick one label, place it on a scale, or say yes/no) and get
calibrated probabilities from a single forward pass. Nothing is
generated, so there is nothing to parse and nothing to hallucinate.

It wraps Laya’s Rust port (`laya-onnx`) through
[extendr](https://extendr.github.io/) and runs on ONNX Runtime. No
Python and no server are needed at prediction time.

> **Status:** early development.

## Installation

**Platforms.** layaR runs on Linux (x86_64 and arm64), Windows (x64) and
Macs with Apple silicon. Intel Macs are not supported: Microsoft
publishes no ONNX Runtime build for them. layaR still installs there,
and runs if you supply ONNX Runtime 1.27 or newer yourself (see
[`?laya_install_runtime`](https://gueyenono.github.io/layaR/reference/laya_install_runtime.md)).

Install from r-universe. On Windows and macOS it gives you a ready-made
binary; on Linux it builds from source (see below):

``` r

install.packages("layaR", repos = c("https://gueyenono.r-universe.dev",
                                    "https://cloud.r-project.org"))
```

Building from source, on Linux or with `install_github()`, needs a Rust
toolchain (rustc 1.88 or newer). On Windows it also needs
[Rtools](https://cran.r-project.org/bin/windows/Rtools/) and Rust’s
`x86_64-pc-windows-gnu` target.

``` r

# install.packages("remotes")
remotes::install_github("gueyenono/layaR")
```

### Getting a model

layaR needs an ONNX export of a Laya checkpoint (1.3 to 1.6 GB each).
[`laya_download_model()`](https://gueyenono.github.io/layaR/reference/laya_download_model.md)
fetches one from
[`gueyenono/laya-onnx`](https://huggingface.co/gueyenono/laya-onnx),
which holds ONNX exports of the three upstream checkpoints (unchanged
weights, Apache-2.0):

``` r

laya_download_model("multilingual")   # also "english" and "typed-decisions"
laya_models()   # (paths shortened)
#>        checkpoint installed                                  path source layout size_gb
#> 1    multilingual      TRUE    ~/.cache/R/layaR/onnx/multilingual  layaR  fused    1.32
#> 2         english     FALSE         ~/.cache/R/layaR/onnx/english   <NA>   <NA>      NA
#> 3 typed-decisions     FALSE ~/.cache/R/layaR/onnx/typed-decisions   <NA>   <NA>      NA
```

To use an export you made yourself with the script from the Laya
repository, import it instead:

``` sh
pip install laya "torch>=2.9" onnx onnxscript onnxruntime transformers safetensors huggingface_hub
python laya-rust/tools/export_onnx.py --model multilingual --out ~/laya-exports
```

``` r

laya_import_model("~/laya-exports/multilingual", "multilingual")
```

[`laya_model_root()`](https://gueyenono.github.io/layaR/reference/laya_model_root.md)
explains where models live. A model exported for Laya’s Rust or
TypeScript SDK (in `~/.cache/laya/onnx`) is found too.

### ONNX Runtime

Models run on [ONNX Runtime](https://onnxruntime.ai), which layaR loads
at run time instead of building it in. The first
[`laya_download_model()`](https://gueyenono.github.io/layaR/reference/laya_download_model.md)
also installs it: a one-time 139 MB download of Microsoft’s official
build (version 1.28.0, from its NuGet package, checked against the
published checksum), of which layaR keeps about 25 MB.
[`laya_install_runtime()`](https://gueyenono.github.io/layaR/reference/laya_install_runtime.md)
does this on its own, and
[`laya_runtime_info()`](https://gueyenono.github.io/layaR/reference/laya_install_runtime.md)
shows which library is used.

## Quickstart

``` r

library(layaR)

questions <- laya_questions(
  department = laya_choice(
    "Which department should handle this request?",
    billing   = "invoices, payments, refunds",
    technical = "bugs, outages, system errors",
    sales     = "pricing, new contracts",
    other     = "everything else"
  ),
  urgency    = laya_score("How urgent is this request?",
                          c("not urgent", "soon", "critical deadline or blocking issue")),
  churn_risk = laya_noul("Does the customer say they will cancel or leave?")
)

state <- list(
  subject = "Duplicate charge on invoice #4411",
  body = "Hi, we were billed twice for March. Please refund the duplicate today or we will cancel our plan."
)

res <- laya_predict(state, questions)
res
#> <laya_result> laya-rl-agent · 3 answers · 235 input tokens
#>   department  choice  billing        p 1.00  confidence 1.00
#>   urgency     score   1.87 (0–2)    confidence 0.64
#>   churn_risk  noul    0.88 → TRUE   confidence 0.88

as.data.frame(res)
#>           id   type  answer  value confidence answer_confidence act_probability abstention
#> 1 department choice billing 1.0000     1.0000            1.0000               1       <NA>
#> 2    urgency  score    1.87 1.8685     0.6371            0.8721               1       <NA>
#> 3 churn_risk   noul    TRUE 0.8782     0.8782            0.8782               1       <NA>
```

The first call loads the model (a few seconds); later calls take a few
hundred milliseconds on a CPU. Wording matters: asking whether the user
“threatens” to cancel misses this ticket, while “says they will cancel”
gets it (see
[`vignette("writing-questions")`](https://gueyenono.github.io/layaR/articles/writing-questions.md)).

The guides cover the rest:
[`vignette("layaR")`](https://gueyenono.github.io/layaR/articles/layaR.md)
to get started, then writing questions, data frames and long documents,
and models and performance. If you work with dplyr and tidyr, see [Using
layaR with the
tidyverse](https://gueyenono.github.io/layaR/articles/tidyverse.html).

### Many states

``` r

tickets <- c("Refund my duplicate charge", "The login page crashes", "What does Pro cost?")
batch <- laya_predict_batch(tickets, questions)
as.data.frame(batch)
```

### Presets, abstention, long documents

``` r

laya_predict(list(message = "My payment failed twice"), laya_preset("triage"))

# Report "abstained" instead of trusting a low-confidence answer
laya_predict(state, questions, min_confidence = 0.8)

# Scan a document longer than the model's context window
laya_predict_long(contract_text, questions)
```

### A data frame in, answers out

``` r

tickets <- data.frame(
  subject = c("Duplicate charge", "App crashes on login"),
  body = c("We were billed twice. Refund it or we cancel.", "Since the update I can't log in.")
)
laya_annotate(tickets, questions, state = c("subject", "body"))
# adds department (a factor), urgency, churn_risk and a _confidence column for each
# a tibble in gives a tibble out, so it works inside a dplyr pipeline too
```

### Emails and languages

``` r

state <- laya_email_state(subject = "Refund", body = raw_body, sender = "ana@example.com")
laya_predict(state, laya_preset("email"))

# Pick a checkpoint: the English one only reads English
laya_detect_language(c("Please refund me", "Me cobraron dos veces. \u00bfPueden devolverme el dinero?"))
```

### Sharing questions with Python

Question sets use the Python SDK’s format, so they move between
languages:

``` r

laya_questions_to_json(questions, "questions.json")
questions <- as_laya_questions("questions.json")
```

## Errors

Every error has class `laya_error` and a specific `laya_error_<kind>`,
so you can handle one kind on its own:

``` r

tryCatch(
  laya_predict(state, questions, max_len = 32),
  laya_error_no_markers = function(e) message("Options don't fit: ", conditionMessage(e))
)
```

## License

Apache License 2.0. Laya and its models are Apache-2.0 (mmBERT-base, the
multilingual backbone, is MIT).
