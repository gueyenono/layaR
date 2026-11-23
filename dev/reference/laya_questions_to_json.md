# Write a question set as JSON

The output is in the Python SDK's format.

## Usage

``` r
laya_questions_to_json(questions, path = NULL, pretty = TRUE)
```

## Arguments

- questions:

  A `laya_questions` object.

- path:

  Optional file path. If given, the JSON is written there.

- pretty:

  Pretty-print the JSON?

## Value

The JSON string (invisibly when `path` is given).

## Examples

``` r
laya_questions_to_json(laya_questions(spam = laya_noul("Is this spam?")))
#> [1] "{\n  \"spam\": {\n    \"type\": \"noul\",\n    \"instructions\": \"Is this spam?\"\n  }\n}\n"
```
