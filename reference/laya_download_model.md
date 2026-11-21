# Download a model

Downloads an exported ONNX checkpoint (1.3 to 1.6 GB) from a Hugging
Face repository into
[`laya_model_path()`](https://gueyenono.github.io/layaR/reference/laya_model_root.md).
The first download also installs ONNX Runtime (see
[`laya_install_runtime()`](https://gueyenono.github.io/layaR/reference/laya_install_runtime.md)).
Files go to a staging folder first, so an interrupted download resumes
where it stopped on the next call and a partial download is never
mistaken for a model.

## Usage

``` r
laya_download_model(
  checkpoint = c("multilingual", "english", "typed-decisions"),
  repo = getOption("layaR.model_repo", "gueyenono/laya-onnx"),
  revision = "main",
  subfolder = NULL,
  token = Sys.getenv("HF_TOKEN"),
  overwrite = FALSE,
  ask = interactive()
)
```

## Arguments

- checkpoint:

  Which checkpoint to download.

- repo:

  The Hugging Face repository, `"owner/name"`. Defaults to the
  `layaR.model_repo` option, or `"gueyenono/laya-onnx"`.

- revision:

  Branch, tag or commit of the repository.

- subfolder:

  Folder of the checkpoint inside the repository. `NULL` uses the
  upstream layout (`multilingual/`, `typed-decisions/`, and the
  repository root for `english`).

- token:

  A Hugging Face access token for private or gated repositories;
  defaults to the `HF_TOKEN` environment variable. The `HF_ENDPOINT`
  environment variable changes the server, as in other Hugging Face
  tools.

- overwrite:

  Replace an installed model?

- ask:

  Ask for confirmation before downloading? Defaults to `TRUE` in
  interactive sessions.

## Value

The model's path, invisibly.

## Details

The Laya authors publish PyTorch weights only, so layaR downloads from
`gueyenono/laya-onnx`, which holds ONNX exports of the three upstream
checkpoints (unchanged weights, Apache-2.0). A repository without an
export gives a `laya_error_model_not_published` error that explains how
to export one and add it with
[`laya_import_model()`](https://gueyenono.github.io/layaR/reference/laya_import_model.md).

## See also

[`laya_models()`](https://gueyenono.github.io/layaR/reference/laya_models.md),
[`laya_import_model()`](https://gueyenono.github.io/layaR/reference/laya_import_model.md)

## Examples

``` r
if (FALSE) { # \dontrun{
laya_download_model("multilingual")
} # }
```
