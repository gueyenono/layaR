# Import an exported model

Adds a checkpoint exported with Laya's `export_onnx.py` (or downloaded
by another tool) to layaR's model root, so
[`laya_engine()`](https://gueyenono.github.io/layaR/dev/reference/laya_engine.md)
finds it by name.

## Usage

``` r
laya_import_model(
  path,
  checkpoint = c("multilingual", "english", "typed-decisions"),
  method = default_import_method(),
  overwrite = FALSE
)
```

## Arguments

- path:

  The export's folder: it holds `model.onnx` (or `encoder.onnx` and
  `head.onnx`), `rl_agent_config.json` and the tokenizer.

- checkpoint:

  Which checkpoint the export is.

- method:

  `"symlink"` links to the folder without copying 1.3 GB; `"copy"`
  copies it, so the original can be deleted. The default is `"symlink"`,
  except on Windows, where links to folders need special permissions and
  only `"copy"` is supported.

- overwrite:

  Replace an installed model?

## Value

The installed path, invisibly.

## Examples

``` r
if (FALSE) { # \dontrun{
laya_import_model("~/exports/onnx/multilingual", "multilingual")
} # }
```
