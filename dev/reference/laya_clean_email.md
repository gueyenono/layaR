# Clean email bodies

Removes quoted replies, reply headers, signatures and legal disclaimers
so the model reads only the sender's message. A port of the Python SDK's
`clean_email_body()`, with the same results.

## Usage

``` r
laya_clean_email(body, max_chars = 3000)
```

## Arguments

- body:

  A character vector of email bodies. `NA` stays `NA`.

- max_chars:

  The most characters to keep, applied after cleaning. Cleaning only
  looks at the first `4 * max_chars` characters, so raise it for long
  messages. As in Python, `0` returns `""` and a negative value trims
  from the end; it never means "no limit".

## Value

A character vector the same length as `body`.

## See also

[`laya_email_state()`](https://gueyenono.github.io/layaR/dev/reference/laya_email_state.md)

## Examples

``` r
laya_clean_email(paste(
  "Please refund the duplicate charge.",
  "",
  "Best,",
  "Ana",
  "",
  "On Mon, 3 Mar 2025 at 10:00, Support <help@example.com> wrote:",
  "> How can we help?",
  sep = "\n"
))
#> [1] "Please refund the duplicate charge."
```
