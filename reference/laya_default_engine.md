# Use the default engine

Returns the engine for `checkpoint`, loading it on first use and caching
it for the rest of the session. Prediction functions use this when no
`engine` is given.

## Usage

``` r
laya_default_engine(checkpoint = getOption("layaR.checkpoint", "multilingual"))
```

## Arguments

- checkpoint:

  The checkpoint; defaults to the `layaR.checkpoint` option, or
  `"multilingual"`.

## Value

A `laya_engine` object.

## Examples

``` r
if (laya_model_available()) laya_default_engine()
```
