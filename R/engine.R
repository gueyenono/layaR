# Engines (plan 7.1). A laya_engine is an environment holding the Rust
# external pointer plus everything needed to rebuild it, so an engine that
# went through saveRDS()/readRDS() (where the pointer becomes NULL)
# reconnects on its next use.

checkpoints <- c("multilingual", "english", "typed-decisions")

#' Load a Laya engine
#'
#' Loads an exported ONNX checkpoint into memory (about 1 to 1.5 GB of RAM)
#' and returns an engine to pass to [laya_predict()] and friends. Create one
#' and reuse it: loading takes several seconds, predictions are fast.
#'
#' Most code never needs this: the prediction functions default to
#' `laya_default_engine()`, which loads the checkpoint named by the
#' `layaR.checkpoint` option (`"multilingual"` by default) on first use and
#' keeps it for the session.
#'
#' Engines can't be sent to other processes. An engine restored with
#' `readRDS()`, or used in a PSOCK worker, reconnects to its model directory
#' on first use, which loads the model again in that process. Don't use
#' engines across `fork()` (e.g. `parallel::mclapply()`): ONNX Runtime's
#' thread pools don't survive it.
#'
#' @param checkpoint Which checkpoint to load: `"multilingual"` (100+
#'   languages, the default), `"english"` (English-optimized) or
#'   `"typed-decisions"` (fine-tuned for four specific workflows).
#' @param model_dir Path to an exported checkpoint directory. Overrides the
#'   lookup by `checkpoint` (see [laya_model_path()]).
#' @param intra_op_threads,inter_op_threads ONNX Runtime thread counts.
#'   `NULL` lets ONNX Runtime choose. The `layaR.threads` option sets the
#'   default for `intra_op_threads`.
#' @param lang_temperatures Optional per-language calibration overrides, a
#'   named list such as
#'   `list(fr = list(temperature = c(1.1, 1, 0.9)))`; see the Python SDK's
#'   `lang_temperatures`. They apply to calls made with a matching `lang`.
#' @return A `laya_engine` object.
#' @seealso [laya_predict()], [laya_engine_info()], [laya_engine_close()]
#' @examples
#' if (laya_model_available()) {
#'   engine <- laya_engine("multilingual", intra_op_threads = 2)
#'   engine
#'   laya_engine_close(engine)
#' }
#' @export
laya_engine <- function(checkpoint = c("multilingual", "english", "typed-decisions"),
                        model_dir = NULL,
                        intra_op_threads = getOption("layaR.threads"),
                        inter_op_threads = NULL,
                        lang_temperatures = NULL) {
  checkpoint <- match.arg(checkpoint)
  explicit_dir <- !is.null(model_dir)
  if (is.null(model_dir)) {
    model_dir <- laya_model_path(checkpoint)
    if (!rs_artifacts_complete(model_dir)) {
      laya_abort(c(
        "No {.val {checkpoint}} model found at {.path {model_dir}}.",
        i = "Export the ONNX model once with Laya's {.file export_onnx.py} and put it there,",
        i = "or point {.arg model_dir} at an existing export, or set the {.envvar LAYA_ONNX_ROOT}",
        " " = "environment variable / {.code options(layaR.model_root = )} to its parent folder."
      ), kind = "model_not_found")
    }
  } else {
    model_dir <- normalizePath(path.expand(model_dir), mustWork = FALSE)
  }
  options <- compact(list(
    intra_op_threads = int_or_null(intra_op_threads, "intra_op_threads"),
    inter_op_threads = int_or_null(inter_op_threads, "inter_op_threads"),
    lang_temperatures = lang_temperatures
  ))
  engine <- new.env(parent = emptyenv())
  engine$model_dir <- model_dir
  # Upstream infers the checkpoint only when it resolves the path itself, so
  # remember it here; an explicit model_dir is "custom" unless the engine knows.
  engine$checkpoint <- if (explicit_dir) NA_character_ else checkpoint
  engine$options_json <- as.character(to_json(options, empty_object = TRUE))
  engine$closed <- FALSE
  engine$ptr <- NULL
  class(engine) <- "laya_engine"
  connect(engine)
  engine
}

connect <- function(engine, call = parent.frame()) {
  engine$ptr <- rs_unwrap(rs_engine_new(engine$model_dir, engine$options_json), call = call)
  engine$info <- from_json(rs_unwrap(rs_engine_info(engine$ptr), call = call))
  invisible(engine)
}

# The live pointer, reconnecting an engine restored by readRDS().
engine_ptr <- function(engine, call = parent.frame()) {
  if (!inherits(engine, "laya_engine")) {
    laya_abort("{.arg engine} must be a {.cls laya_engine} from {.fn laya_engine}.",
               kind = "invalid_argument", call = call)
  }
  if (isTRUE(engine$closed)) {
    laya_abort("This engine was closed with {.fn laya_engine_close}; create a new one.",
               kind = "bridge_engine_closed", call = call)
  }
  if (!rs_engine_is_live(engine$ptr)) {
    cli::cli_inform(c(i = "Reconnecting a restored engine to {.path {engine$model_dir}}."),
                    class = "laya_reconnect")
    connect(engine, call = call)
  }
  engine$ptr
}

#' Use the default engine
#'
#' Returns the engine for `checkpoint`, loading it on first use and caching
#' it for the rest of the session. Prediction functions use this when no
#' `engine` is given.
#'
#' @param checkpoint The checkpoint; defaults to the `layaR.checkpoint`
#'   option, or `"multilingual"`.
#' @return A `laya_engine` object.
#' @examples
#' if (laya_model_available()) laya_default_engine()
#' @export
laya_default_engine <- function(checkpoint = getOption("layaR.checkpoint", "multilingual")) {
  checkpoint <- match.arg(checkpoint, checkpoints)
  cached <- the$engines[[checkpoint]]
  if (is.null(cached) || isTRUE(cached$closed)) {
    cached <- laya_engine(checkpoint)
    the$engines[[checkpoint]] <- cached
  }
  cached
}

#' Inspect or close an engine
#'
#' `laya_engine_info()` reports what an engine loaded: checkpoint, ONNX
#' layout, file paths, sequence budgets (`max_len`, `head_max_len`) and
#' calibration temperatures. `laya_engine_close()` frees the model's memory
#' right away instead of waiting for garbage collection; the engine can't be
#' used afterwards.
#'
#' @param engine A `laya_engine`.
#' @return `laya_engine_info()` returns a list; `laya_engine_close()` returns
#'   `engine`, invisibly.
#' @examples
#' if (laya_model_available()) {
#'   engine <- laya_engine()
#'   str(laya_engine_info(engine), max.level = 1)
#'   laya_engine_close(engine)
#' }
#' @export
laya_engine_info <- function(engine) {
  engine_ptr(engine)
  engine$info
}

#' @rdname laya_engine_info
#' @export
laya_engine_close <- function(engine) {
  if (!inherits(engine, "laya_engine")) {
    laya_abort("{.arg engine} must be a {.cls laya_engine}.", kind = "invalid_argument")
  }
  if (!is.null(engine$ptr)) rs_unwrap(rs_engine_close(engine$ptr))
  engine$closed <- TRUE
  for (k in names(the$engines)) {
    if (identical(the$engines[[k]], engine)) the$engines[[k]] <- NULL
  }
  invisible(engine)
}

#' @export
format.laya_engine <- function(x, ...) {
  info <- x$info
  state <- if (isTRUE(x$closed)) " (closed)" else ""
  c(
    sprintf("<laya_engine> %s \u00b7 %s ONNX \u00b7 max_len %s \u00b7 head_max_len %s%s",
            info$checkpoint %||% (if (is.na(x$checkpoint %||% NA)) "custom" else x$checkpoint),
            info$layout %||% "?",
            info$max_len %||% "?", info$head_max_len %||% "?", state),
    paste0("  ", x$model_dir)
  )
}

#' @export
print.laya_engine <- function(x, ...) {
  cat(format(x), sep = "\n")
  invisible(x)
}

# ---- model locations (the full set of model helpers comes in Phase 5) ----

#' Where models live
#'
#' layaR looks for exported checkpoints in a model root folder with one
#' subfolder per checkpoint (`multilingual/`, `english/`,
#' `typed-decisions/`). The root is, in order: the `layaR.model_root`
#' option, the `LAYA_ONNX_ROOT` environment variable (shared with Laya's
#' Rust SDK), or the user cache folder `tools::R_user_dir("layaR", "cache")`
#' plus `onnx/`.
#'
#' @param checkpoint A checkpoint name.
#' @return `laya_model_root()` and `laya_model_path()` return paths;
#'   `laya_model_available()` returns `TRUE` when a complete export is found.
#' @examples
#' laya_model_root()
#' laya_model_path("english")
#' laya_model_available()
#' @export
laya_model_root <- function() {
  root <- getOption("layaR.model_root")
  if (is.null(root) || !nzchar(root)) root <- Sys.getenv("LAYA_ONNX_ROOT")
  if (!nzchar(root)) root <- file.path(tools::R_user_dir("layaR", "cache"), "onnx")
  normalizePath(path.expand(root), mustWork = FALSE)
}

#' @rdname laya_model_root
#' @export
laya_model_path <- function(checkpoint = c("multilingual", "english", "typed-decisions")) {
  checkpoint <- match.arg(checkpoint)
  file.path(laya_model_root(), checkpoint)
}

#' @rdname laya_model_root
#' @export
laya_model_available <- function(checkpoint = getOption("layaR.checkpoint", "multilingual")) {
  checkpoint <- match.arg(checkpoint, checkpoints)
  rs_artifacts_complete(laya_model_path(checkpoint))
}

# ---- small helpers ----

compact <- function(x) x[!vapply(x, is.null, logical(1))]

`%||%` <- function(x, y) if (is.null(x)) y else x

int_or_null <- function(x, arg, call = parent.frame()) {
  if (is.null(x)) return(NULL)
  if (!is.numeric(x) || length(x) != 1 || is.na(x) || x < 0 || x != round(x)) {
    laya_abort("{.arg {arg}} must be a single non-negative whole number or {.code NULL}.",
               kind = "invalid_argument", call = call)
  }
  as.integer(x)
}
