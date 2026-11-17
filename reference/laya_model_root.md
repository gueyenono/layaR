# Where models live

layaR keeps exported checkpoints in a model root folder with one
subfolder per checkpoint (`multilingual/`, `english/`,
`typed-decisions/`). The root is, in order: the `layaR.model_root`
option, the `LAYA_ONNX_ROOT` environment variable (shared with Laya's
Rust SDK), or the user cache folder
`tools::R_user_dir("layaR", "cache")` plus `onnx/`. Downloads and
imports go there.

## Usage

``` r
laya_model_root()

laya_model_path(checkpoint = c("multilingual", "english", "typed-decisions"))

laya_model_available(
  checkpoint = getOption("layaR.checkpoint", "multilingual")
)
```

## Arguments

- checkpoint:

  A checkpoint name.

## Value

`laya_model_root()` and `laya_model_path()` return paths (the latter is
where layaR installs `checkpoint`); `laya_model_available()` returns
`TRUE` when a complete export is found in either place.

## Details

When a checkpoint isn't in the model root, layaR also looks in the cache
that Laya's other SDKs share (`~/.cache/laya/onnx`, or
`%LOCALAPPDATA%/laya/onnx` on Windows), so a model exported or
downloaded for the Rust or TypeScript SDK is reused. layaR never writes
there. Set `options(layaR.shared_cache = FALSE)` to turn this off.

## See also

[`laya_models()`](https://gueyenono.github.io/layaR/reference/laya_models.md),
[`laya_download_model()`](https://gueyenono.github.io/layaR/reference/laya_download_model.md),
[`laya_import_model()`](https://gueyenono.github.io/layaR/reference/laya_import_model.md)

## Examples

``` r
laya_model_root()
#> [1] "/home/runner/.cache/R/layaR/onnx"
laya_model_path("english")
#> [1] "/home/runner/.cache/R/layaR/onnx/english"
laya_model_available()
#> [1] FALSE
```
