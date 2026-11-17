# Laya results

A `laya_result` is a list with `model`, `answers` (one entry per
question, in question order) and `usage` (token accounting and
truncation flags), in the Python SDK's shape. Each answer has `type`,
`confidence`, `answer_confidence` and `action$act_probability`, plus:

## Usage

``` r
# S3 method for class 'laya_result'
as.data.frame(x, row.names = NULL, optional = FALSE, ...)

laya_probabilities(x)

laya_answer(x, id)

# S3 method for class 'laya_batch_result'
as.data.frame(x, row.names = NULL, optional = FALSE, ...)
```

## Arguments

- x:

  A `laya_result` or `laya_batch_result`.

- row.names, optional:

  Ignored; part of the
  [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html)
  generic.

- ...:

  Unused.

- id:

  A question id.

## Value

[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) returns a
data frame with columns `id`, `type`, `answer` (the label, the score or
`TRUE`/`FALSE`, as text), `value` (the chosen label's probability, the
score, or P(true)), `confidence`, `answer_confidence`, `act_probability`
and `abstention`. `laya_probabilities()` returns columns `id`, `type`,
`option` and `probability` (for noul questions, options `"false"` and
`"true"`).

## Details

- choice: `choice` (the top label) and `probabilities` (per label);

- score: `score` (the expected level, from 0 to levels - 1), `legend`
  and `probabilities` (per level, keyed `"0"`, `"1"`, ...);

- noul: `noul` (the probability the statement holds).

With `min_confidence`, answers also carry `abstention` and
`abstention_threshold`; from
[`laya_predict_long()`](https://gueyenono.github.io/layaR/reference/laya_predict.md),
`window`.

[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) gives one
row per question; `laya_probabilities()` one row per option;
`laya_answer()` extracts one answer. A `laya_batch_result` (from
[`laya_predict_batch()`](https://gueyenono.github.io/layaR/reference/laya_predict.md))
is a list of `laya_result`s whose data-frame forms carry a `state_id`
column.

## Examples

``` r
if (laya_model_available()) {
  res <- laya_predict("Refund me now!", laya_preset("triage"))
  as.data.frame(res)
  laya_probabilities(res)
  laya_answer(res, "intent")$choice
}
```
