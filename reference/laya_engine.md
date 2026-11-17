# Load a Laya engine

Loads an exported ONNX checkpoint into memory (about 1 to 1.5 GB of RAM)
and returns an engine to pass to
[`laya_predict()`](https://gueyenono.github.io/layaR/reference/laya_predict.md)
and friends. Create one and reuse it: loading takes several seconds,
predictions are fast.

## Usage

``` r
laya_engine(
  checkpoint = c("multilingual", "english", "typed-decisions"),
  model_dir = NULL,
  intra_op_threads = getOption("layaR.threads"),
  inter_op_threads = NULL,
  lang_temperatures = NULL
)
```

## Arguments

- checkpoint:

  Which checkpoint to load: `"multilingual"` (100+ languages, the
  default), `"english"` (English-optimized) or `"typed-decisions"`
  (fine-tuned for four specific workflows).

- model_dir:

  Path to an exported checkpoint directory. Overrides the lookup by
  `checkpoint` (see
  [`laya_model_path()`](https://gueyenono.github.io/layaR/reference/laya_model_root.md)).

- intra_op_threads, inter_op_threads:

  ONNX Runtime thread counts. `NULL` lets ONNX Runtime choose. The
  `layaR.threads` option sets the default for `intra_op_threads`.

- lang_temperatures:

  Optional per-language calibration overrides, a named list such as
  `list(fr = list(temperature = c(1.1, 1, 0.9)))`; see the Python SDK's
  `lang_temperatures`. They apply to calls made with a matching `lang`.

## Value

A `laya_engine` object.

## Details

Most code never needs this: the prediction functions default to
[`laya_default_engine()`](https://gueyenono.github.io/layaR/reference/laya_default_engine.md),
which loads the checkpoint named by the `layaR.checkpoint` option
(`"multilingual"` by default) on first use and keeps it for the session.

Engines can't be sent to other processes. An engine restored with
[`readRDS()`](https://rdrr.io/r/base/readRDS.html), or used in a PSOCK
worker
([`parallel::makePSOCKcluster()`](https://rdrr.io/r/parallel/makeCluster.html),
`future::multisession`), reconnects to its model directory on first use,
which loads the model again in that process (another 1 to 1.5 GB each).

Engines don't work across `fork()`
([`parallel::mclapply()`](https://rdrr.io/r/parallel/mclapply.html),
`future::multicore`): ONNX Runtime's thread pools don't survive it, so a
forked child could hang. Using an engine in a forked child raises a
`laya_error_forked` error instead. A single engine already runs one
forward pass on several cores; for more throughput use
[`laya_predict_batch()`](https://gueyenono.github.io/layaR/reference/laya_predict.md),
or PSOCK workers that each load their own engine.

## See also

[`laya_predict()`](https://gueyenono.github.io/layaR/reference/laya_predict.md),
[`laya_engine_info()`](https://gueyenono.github.io/layaR/reference/laya_engine_info.md),
[`laya_engine_close()`](https://gueyenono.github.io/layaR/reference/laya_engine_info.md)

## Examples

``` r
if (laya_model_available()) {
  engine <- laya_engine("multilingual", intra_op_threads = 2)
  engine
  laya_engine_close(engine)
}
```
