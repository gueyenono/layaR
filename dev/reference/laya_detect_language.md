# Detect the language of states

Reads each state's text (string values only; keys are ignored) and
reports its dominant script, a best-effort language guess for
Latin-script text, and whether the English checkpoint can read it. Use
it to pick a checkpoint: `"english"` when `is_english` is `TRUE`,
`"multilingual"` otherwise. No model is needed.

## Usage

``` r
laya_detect_language(states)
```

## Arguments

- states:

  A character vector of texts, a single state (a named list), a list of
  states, or a data frame (one state per row).

## Value

A data frame with one row per state and columns `script`, `language` (an
ISO 639-1 code, or `NA` when undecided or not Latin), `is_english`,
`language_undecided`, `diacritic_rate`, `non_latin_fraction`,
`mixed_segment` and `script_profile` (a list-column of named numeric
vectors: the share of letters in each script).

## Details

A structured state that reads English as a whole is also checked field
by field and line by line, so a short message in another language next
to a long English stack trace still counts as non-English
(`mixed_segment` shows the part that decided it).

## Examples

``` r
laya_detect_language(c(
  "Please refund the duplicate charge",
  "मार्च का बिल दो बार लिया गया",
  "glömt lösenord"
))
#>       script language is_english language_undecided diacritic_rate
#> 1      latin       en       TRUE              FALSE         0.0000
#> 2 devanagari     <NA>      FALSE               TRUE         0.0000
#> 3      latin       sv      FALSE              FALSE         0.1429
#>   non_latin_fraction mixed_segment script_profile
#> 1                  0          <NA>              1
#> 2                  1          <NA>              1
#> 3                  0          <NA>              1
laya_detect_language(list(
  subject = "Refund",
  body = "Hola, me cobraron dos veces. \u00bfPueden devolverme el dinero?"
))
#>   script language is_english language_undecided diacritic_rate
#> 1  latin       es      FALSE              FALSE              0
#>   non_latin_fraction mixed_segment script_profile
#> 1                  0          <NA>              1
```
