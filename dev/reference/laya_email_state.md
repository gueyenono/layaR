# Build an email state

Builds the state the Python SDK's `email_state()` builds: `subject`, a
cleaned `body`, `from` when a `sender` is given, then any extra fields.
Pass the result to
[`laya_predict()`](https://gueyenono.github.io/layaR/dev/reference/laya_predict.md),
or use it with the `"email"` preset
([`laya_preset()`](https://gueyenono.github.io/layaR/dev/reference/laya_preset.md)).

## Usage

``` r
laya_email_state(
  subject,
  body,
  sender = NULL,
  ...,
  clean = TRUE,
  max_chars = 3000
)
```

## Arguments

- subject, body:

  The email's subject and body, single strings.

- sender:

  Optional sender address, stored in the state's `from` field.

- ...:

  Extra named fields to add to the state (for example
  `ticket_id = 4411`). `NULL` fields are dropped, as in Python.

- clean:

  Clean the body with
  [`laya_clean_email()`](https://gueyenono.github.io/layaR/dev/reference/laya_clean_email.md)?
  If `FALSE` the body is passed through whole.

- max_chars:

  Passed to
  [`laya_clean_email()`](https://gueyenono.github.io/layaR/dev/reference/laya_clean_email.md)
  when `clean = TRUE`.

## Value

A named list, ready to use as a state.

## Examples

``` r
laya_email_state(
  subject = "Duplicate charge",
  body = "We were billed twice.\n\n-- \nAna Muller\nAcme Corp",
  sender = "ana@example.com",
  ticket_id = 4411L
)
#> $subject
#> [1] "Duplicate charge"
#> 
#> $body
#> [1] "We were billed twice."
#> 
#> $from
#> [1] "ana@example.com"
#> 
#> $ticket_id
#> [1] 4411
#> 
```
