# List checkpoints and whether they are installed

List checkpoints and whether they are installed

## Usage

``` r
laya_models()
```

## Value

A data frame with one row per checkpoint: `checkpoint`, `installed`,
`path` (where it was found, or where it would be installed), `source`
(`"layaR"` for the model root, `"shared"` for the cross-SDK cache, `NA`
when not installed), `layout` (`"fused"` or `"split"`) and `size_gb`.

## Examples

``` r
laya_models()
#>        checkpoint installed                                             path
#> 1    multilingual     FALSE    /home/runner/.cache/R/layaR/onnx/multilingual
#> 2         english     FALSE         /home/runner/.cache/R/layaR/onnx/english
#> 3 typed-decisions     FALSE /home/runner/.cache/R/layaR/onnx/typed-decisions
#>   source layout size_gb
#> 1   <NA>   <NA>      NA
#> 2   <NA>   <NA>      NA
#> 3   <NA>   <NA>      NA
```
