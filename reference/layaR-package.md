# layaR: Local Laya Decision Models via Rust

Run Laya System 1 decision models (typed choice, score and yes/no
questions with calibrated probabilities) locally from R, through the
laya-onnx Rust crate and ONNX Runtime. No Python or server is required
at prediction time.

## Options

layaR reads these options; set them with
[`options()`](https://rdrr.io/r/base/options.html), for example in your
`.Rprofile`.

- `layaR.checkpoint`: the checkpoint
  [`laya_default_engine()`](https://gueyenono.github.io/layaR/reference/laya_default_engine.md)
  loads (`"multilingual"` by default).

- `layaR.threads`: the default `intra_op_threads` for
  [`laya_engine()`](https://gueyenono.github.io/layaR/reference/laya_engine.md)
  (`NULL`: ONNX Runtime chooses).

- `layaR.batch_size`: the default `batch_size` for
  [`laya_predict_batch()`](https://gueyenono.github.io/layaR/reference/laya_predict.md)
  and
  [`laya_annotate()`](https://gueyenono.github.io/layaR/reference/laya_annotate.md)
  (1).

- `layaR.model_root`: where models are installed (see
  [`laya_model_root()`](https://gueyenono.github.io/layaR/reference/laya_model_root.md)).

- `layaR.model_repo`: the Hugging Face repository
  [`laya_download_model()`](https://gueyenono.github.io/layaR/reference/laya_download_model.md)
  uses (`"gueyenono/laya-onnx"`).

- `layaR.onnxruntime`: the path of an ONNX Runtime library to load
  instead of the one
  [`laya_install_runtime()`](https://gueyenono.github.io/layaR/reference/laya_install_runtime.md)
  downloads.

- `layaR.shared_cache`: `FALSE` stops layaR from looking for models in
  the cache shared with Laya's Rust and TypeScript SDKs.

## See also

Useful links:

- <https://gueyenono.github.io/layaR/>

- <https://github.com/gueyenono/layaR>

- Report bugs at <https://github.com/gueyenono/layaR/issues>

## Author

**Maintainer**: G. Nono Ghislain <nonoghislain@gmail.com>

Authors:

- G. Nono Ghislain <nonoghislain@gmail.com>

Other contributors:

- Convai Innovations (laya-onnx Rust crate and the test fixtures derived
  from its golden tests) \[copyright holder\]

- Authors of the dependency Rust crates (see LICENSE.note) \[copyright
  holder\]
