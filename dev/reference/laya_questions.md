# Combine questions into a question set

Combine questions into a question set

## Usage

``` r
laya_questions(...)
```

## Arguments

- ...:

  Named questions built with
  [`laya_choice()`](https://gueyenono.github.io/layaR/dev/reference/laya_question.md),
  [`laya_score()`](https://gueyenono.github.io/layaR/dev/reference/laya_question.md)
  or
  [`laya_noul()`](https://gueyenono.github.io/layaR/dev/reference/laya_question.md).
  The names are the question ids used in the results.

## Value

A `laya_questions` object: a named list of questions in the Python SDK's
format.

## See also

[`as_laya_questions()`](https://gueyenono.github.io/layaR/dev/reference/as_laya_questions.md)
to import a Python question set, and
[`laya_questions_to_json()`](https://gueyenono.github.io/layaR/dev/reference/laya_questions_to_json.md)
to export one.

## Examples

``` r
qs <- laya_questions(
  department = laya_choice("Which department?", billing = "refunds", technical = "bugs"),
  urgency = laya_score("How urgent?", c("low", "high")),
  churn_risk = laya_noul("Does the user threaten to cancel?")
)
qs
#> <laya_questions> 3 questions
#>   department  choice Which department?  [2 options: billing, technical]
#>   urgency     score  How urgent?  [2 levels]
#>   churn_risk  noul   Does the user threaten to cancel?  [yes/no]
```
