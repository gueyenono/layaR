# Validate a question set without a model

Runs the Rust engine's own question validation, so errors surface before
a model is loaded.

## Usage

``` r
laya_validate_questions(questions)
```

## Arguments

- questions:

  A `laya_questions` object, or anything
  [`as_laya_questions()`](https://gueyenono.github.io/layaR/reference/as_laya_questions.md)
  accepts.

## Value

`questions` as a `laya_questions` object, invisibly. Errors with a
`laya_error_invalid_question` (or `laya_error_not_supported`) condition.

## Examples

``` r
laya_validate_questions(laya_questions(spam = laya_noul("Is this spam?")))
```
