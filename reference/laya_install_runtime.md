# Install ONNX Runtime

layaR runs models on [ONNX Runtime](https://onnxruntime.ai), which it
loads when the first engine is created rather than building it in. On
first use layaR downloads Microsoft's official build (version 1.28.0,
MIT license) from its NuGet package `Microsoft.ML.OnnxRuntime` (about
139 MB, checked against the SHA-512 that nuget.org publishes) and keeps
only this platform's library (about 25 MB) in
`tools::R_user_dir("layaR", "data")`.
[`laya_download_model()`](https://gueyenono.github.io/layaR/reference/laya_download_model.md)
does this for you; call `laya_install_runtime()` to do it on its own,
for example before going offline.

## Usage

``` r
laya_install_runtime(overwrite = FALSE, ask = interactive())

laya_runtime_info()
```

## Arguments

- overwrite:

  Download again even if the library is installed?

- ask:

  Ask for confirmation before downloading? Defaults to `TRUE` in
  interactive sessions.

## Value

`laya_install_runtime()` returns the library's path, invisibly.
`laya_runtime_info()` returns a list: the `version` layaR installs, the
`path` and `source` (`"option"`, `"ORT_DYLIB_PATH"` or `"layaR"`) of the
library it would load, whether layaR's own copy is `installed`, whether
a library is `loaded`, and, once loaded, its `loaded_path`,
`loaded_version` and ONNX Runtime's `build_info`.

## Details

Microsoft publishes builds for Linux (x86_64 and arm64), macOS on Apple
silicon and Windows (x64). Elsewhere, Intel Macs included, install ONNX
Runtime 1.27 or newer yourself and point layaR at the library with
`options(layaR.onnxruntime = "/path/to/libonnxruntime.dylib")` or the
`ORT_DYLIB_PATH` environment variable. Either one also overrides the
downloaded library on supported platforms.

The library is loaded once per R session. To switch to another one,
restart R.

## See also

[`laya_download_model()`](https://gueyenono.github.io/layaR/reference/laya_download_model.md)

## Examples

``` r
laya_runtime_info()
#> $version
#> [1] "1.28.0"
#> 
#> $path
#> [1] "/home/runner/.local/share/R/layaR/onnxruntime/1.28.0/libonnxruntime.so"
#> 
#> $source
#> [1] NA
#> 
#> $installed
#> [1] FALSE
#> 
#> $loaded
#> [1] FALSE
#> 
#> $loaded_path
#> [1] NA
#> 
#> $loaded_version
#> [1] NA
#> 
#> $build_info
#> [1] NA
#> 
if (FALSE) { # \dontrun{
laya_install_runtime()
} # }
```
