#' @keywords internal
#' @section Options:
#' layaR reads these options; set them with [options()], for example in your
#' `.Rprofile`.
#'
#' * `layaR.checkpoint`: the checkpoint [laya_default_engine()] loads
#'   (`"multilingual"` by default).
#' * `layaR.threads`: the default `intra_op_threads` for [laya_engine()]
#'   (`NULL`: ONNX Runtime chooses).
#' * `layaR.batch_size`: the default `batch_size` for [laya_predict_batch()]
#'   and [laya_annotate()] (1).
#' * `layaR.model_root`: where models are installed (see
#'   [laya_model_root()]).
#' * `layaR.model_repo`: the Hugging Face repository
#'   [laya_download_model()] uses (`"gueyenono/laya-onnx"`).
#' * `layaR.shared_cache`: `FALSE` stops layaR from looking for models in the
#'   cache shared with Laya's Rust and TypeScript SDKs.
"_PACKAGE"
