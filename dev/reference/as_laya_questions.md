# Convert to a question set

Accepts a question set in the Python SDK's format, so question sets can
be shared between Python and R: an R list, a JSON string, or the path to
a `.json` file.

## Usage

``` r
as_laya_questions(x, ...)
```

## Arguments

- x:

  A `laya_questions` object, a named list in the Python format
  (`list(id = list(type = , instructions = , criteria = ))`), a JSON
  string, or a path to a JSON file.

- ...:

  Unused.

## Value

A `laya_questions` object.

## Examples

``` r
as_laya_questions('{
  "urgency": {"type": "score", "instructions": "How urgent?",
              "criteria": ["low", "high"]}
}')
#> <laya_questions> 1 question
#>   urgency  score  How urgent?  [2 levels]
```
