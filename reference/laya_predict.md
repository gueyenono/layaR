# Answer typed questions about a state

`laya_predict()` answers every question about one state in a single
forward pass. `laya_predict_batch()` does the same for many states.
`laya_predict_long()` scans a state longer than the model's context in
overlapping windows and keeps, per question, the most confident window.

## Usage

``` r
laya_predict(
  state,
  questions,
  engine = laya_default_engine(),
  ...,
  min_confidence = NULL,
  lang = NULL,
  max_len = NULL,
  head_max_len = NULL
)

laya_predict_batch(
  states,
  questions,
  engine = laya_default_engine(),
  ...,
  batch_size = getOption("layaR.batch_size", 1L),
  sort_by_length = FALSE,
  min_confidence = NULL,
  lang = NULL,
  max_len = NULL,
  head_max_len = NULL,
  chunk_size = 64L,
  progress = interactive()
)

laya_predict_long(
  state,
  questions,
  engine = laya_default_engine(),
  ...,
  window = NULL,
  stride = NULL,
  batch_size = NULL,
  lang = NULL
)

# S3 method for class 'laya_engine'
predict(object, state, questions, ...)
```

## Arguments

- state:

  A string, a named list, or a one-row data frame.

- questions:

  A question set from
  [`laya_questions()`](https://gueyenono.github.io/layaR/reference/laya_questions.md)
  or
  [`laya_preset()`](https://gueyenono.github.io/layaR/reference/laya_preset.md),
  or anything
  [`as_laya_questions()`](https://gueyenono.github.io/layaR/reference/as_laya_questions.md)
  accepts.

- engine:

  A
  [`laya_engine()`](https://gueyenono.github.io/layaR/reference/laya_engine.md).
  Defaults to
  [`laya_default_engine()`](https://gueyenono.github.io/layaR/reference/laya_default_engine.md).

- ...:

  Must be empty; the options below are named.

- min_confidence:

  Optional abstention gate: a threshold in `[0, 1]`, or a named numeric
  vector of thresholds per option-count bucket (names from
  [`laya_bucket_keys()`](https://gueyenono.github.io/layaR/reference/laya_bucket_keys.md),
  plus `"default"`). The threshold is compared with each answer's
  `answer_confidence` (for a choice question, the chosen option's
  probability), as in the Python SDK. Every answer then reports
  `abstention`: `"passed"`, `"abstained"` or `"unevaluated"`.

- lang:

  Optional language code (e.g. `"fr"`) selecting per-language
  calibration temperatures, when the engine has them.

- max_len, head_max_len:

  Optional per-call token budgets overriding the checkpoint's: the whole
  sequence, and the part spent on a question's options.

- states:

  A character vector, a list of states, or a data frame (each row
  becomes a named list).

- batch_size:

  States per forward pass. Defaults to the `layaR.batch_size` option, or
  1: on a CPU, one state per pass is usually fastest, because a batch
  pads every state to the longest one (see
  [`vignette("models-and-performance", package = "layaR")`](https://gueyenono.github.io/layaR/articles/models-and-performance.md)).
  Larger batches can pay off on other hardware. `NULL` sends each chunk
  in one pass, as the Python SDK does by default. Results are the same
  either way.

- sort_by_length:

  Group similarly sized states within a chunk to reduce padding (only
  with a `batch_size` above 1 and smaller than the chunk).

- chunk_size:

  States sent to the engine per call. Between chunks R can be
  interrupted and the progress bar updates.

- progress:

  Show a progress bar? Defaults to `TRUE` in interactive sessions with
  more than one chunk.

- window, stride:

  Optional scan window and stride, in tokens. By default the window is
  the room the questions leave in one sequence and the stride is half
  the window.

- object:

  A `laya_engine`, for the
  [`stats::predict()`](https://rdrr.io/r/stats/predict.html) method.

## Value

`laya_predict()` and `laya_predict_long()` return a `laya_result`;
`laya_predict_batch()` returns a `laya_batch_result` (a list of
`laya_result`s, in input order). See
[laya_result](https://gueyenono.github.io/layaR/reference/laya_result.md)
for how to read them.

## Details

A state is either a single string, used verbatim, or a named list, which
the model reads as a JSON object (field order is kept). A one-row data
frame is read as a named list.

## Examples

``` r
if (laya_model_available()) {
  qs <- laya_questions(
    department = laya_choice("Which department should handle this?",
                             billing = "invoices, refunds",
                             technical = "bugs, outages"),
    churn_risk = laya_noul("Does the user threaten to cancel?")
  )
  res <- laya_predict("I was billed twice. Refund me or I cancel.", qs)
  res
  as.data.frame(res)

  laya_predict_batch(c("Refund please", "The app crashes"), qs)
}
```
