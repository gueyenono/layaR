# Annotate a data frame

Asks the same questions about every row of a data frame and adds the
answers as new columns, one or more per question:

## Usage

``` r
laya_annotate(
  data,
  questions,
  state,
  engine = laya_default_engine(),
  ...,
  prefix = "",
  confidence = TRUE,
  answer_confidence = FALSE,
  probabilities = FALSE
)
```

## Arguments

- data:

  A data frame or tibble. A tibble stays a tibble.

- questions:

  A question set
  ([`laya_questions()`](https://gueyenono.github.io/layaR/dev/reference/laya_questions.md),
  a preset, or anything
  [`as_laya_questions()`](https://gueyenono.github.io/layaR/dev/reference/as_laya_questions.md)
  accepts).

- state:

  The name or names of the column(s) the model reads, as strings
  (`"text"`, `c("subject", "body")`), not bare names. With one column,
  its text is the state as is. With several, each row becomes a
  structured state such as `{"subject": ..., "body": ...}`, which keeps
  the field names as context for the model.

- engine:

  A
  [`laya_engine()`](https://gueyenono.github.io/layaR/dev/reference/laya_engine.md).
  Defaults to
  [`laya_default_engine()`](https://gueyenono.github.io/layaR/dev/reference/laya_default_engine.md).

- ...:

  Passed to
  [`laya_predict_batch()`](https://gueyenono.github.io/layaR/dev/reference/laya_predict.md):
  `min_confidence`, `lang`, `batch_size`, `chunk_size`, `progress` and
  the token budgets.

- prefix:

  A prefix for the new column names, for example `"laya_"`.

- confidence:

  Add a `<id>_confidence` column per question?

- answer_confidence:

  Add a `<id>_answer_confidence` column per question: the confidence in
  the answer given, which `min_confidence` compares with its threshold.
  For a choice question it is the chosen option's probability.

- probabilities:

  Add a `<id>_probabilities` list-column per question, holding each
  option's probability as a named numeric vector?

## Value

`data` with the new columns. Rows whose state columns are all missing
get `NA` answers instead of a prediction.

## Details

- a choice question gives a factor whose levels are the options, in
  order;

- a score question gives the expected level (a number from 0 to the
  number of levels minus one);

- a yes/no question gives the probability that the statement is true.

With `confidence = TRUE` each answer also gets a `<id>_confidence`
column. With `min_confidence` (passed in `...`), each gated answer also
gets a logical `<id>_abstained` column. The answer is kept either way;
filter on the column to drop low-confidence answers. The gate compares
the threshold with each answer's `answer_confidence` (for a choice
question, the chosen option's probability), which can differ from the
`<id>_confidence` column; `answer_confidence = TRUE` adds it as a
`<id>_answer_confidence` column.

## See also

[`laya_predict_batch()`](https://gueyenono.github.io/layaR/dev/reference/laya_predict.md)
for the full results.

## Examples

``` r
if (laya_model_available()) {
  tickets <- data.frame(
    subject = c("Duplicate charge", "App crashes on login"),
    body = c("We were billed twice. Refund it or we cancel.", "Since the update I can't log in.")
  )
  qs <- laya_questions(
    department = laya_choice("Which department should handle this?",
                             billing = "invoices, refunds", technical = "bugs, outages"),
    churn_risk = laya_noul("Does the customer threaten to cancel?")
  )
  laya_annotate(tickets, qs, state = c("subject", "body"))
}
```
