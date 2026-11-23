# Build Laya questions

Laya answers three kinds of typed question about a state in one forward
pass:

## Usage

``` r
laya_choice(instructions, ..., .options = NULL)

laya_score(instructions, levels)

laya_noul(instructions, if_false = NULL, if_true = NULL)
```

## Arguments

- instructions:

  The question, as a string. A list is also accepted and is serialized
  to JSON, as the Python SDK does for structured instructions.

- ...:

  For `laya_choice()`, the options: either named arguments
  (`label = "description"`) or unnamed labels without descriptions.
  Option order matters: the model scores one marker per option, in
  order.

- .options:

  Alternatively, the options as a named character vector or list (labels
  with descriptions), or an unnamed character vector (labels only).

- levels:

  For `laya_score()`, the levels from lowest to highest, as a character
  vector or a list of structured levels.

- if_false, if_true:

  For `laya_noul()`, optional descriptions of what the false and true
  sides mean.

## Value

A `laya_question` object.

## Details

- `laya_choice()`: pick one label from a fixed set of options.

- `laya_score()`: place the state on an ordinal scale (levels lowest
  first); the answer is the expected level, a number between 0 and the
  number of levels minus one.

- `laya_noul()`: a yes/no statement; the answer is the calibrated
  probability that it holds.

Combine questions into a set with
[`laya_questions()`](https://gueyenono.github.io/layaR/dev/reference/laya_questions.md).

## See also

[`laya_questions()`](https://gueyenono.github.io/layaR/dev/reference/laya_questions.md),
[`laya_preset()`](https://gueyenono.github.io/layaR/dev/reference/laya_preset.md)

## Examples

``` r
laya_choice(
  "Which department should handle this request?",
  billing = "invoices, payments, refunds",
  technical = "bugs, outages, system errors",
  other = "everything else"
)
#> <laya_question> choice Which department should handle this request?  [3 options: billing, technical, other]
laya_choice("What is this about?", "coding", "writing", "other")
#> <laya_question> choice What is this about?  [3 options: coding, writing, other]
laya_score("How urgent is this request?", c("not urgent", "soon", "blocking"))
#> <laya_question> score  How urgent is this request?  [3 levels]
laya_noul("Is this email a phishing attempt?",
          if_false = "a legitimate email", if_true = "phishing or fraud")
#> <laya_question> noul   Is this email a phishing attempt?  [yes/no]
```
