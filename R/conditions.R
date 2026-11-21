# Unwrapping the bridge envelope and raising classed conditions (plan D4, D5).
#
# Every `rs_*` call (except the plain predicates) returns
# list(ok, value, error_kind, error_message, warnings). Warnings are replayed as
# `laya_warning` conditions; errors become `laya_error_<kind>` conditions, so
# callers can catch one kind specifically:
#   tryCatch(..., laya_error_no_markers = function(e) ...)

rs_unwrap <- function(res, call = parent.frame()) {
  for (w in res$warnings) {
    cli::cli_warn("{w}", class = "laya_warning")
  }
  if (!isTRUE(res$ok)) {
    msg <- res$error_message
    laya_abort("{msg}", kind = res$error_kind, call = call)
  }
  res$value
}

#' Laya conditions
#'
#' Every error layaR raises has class `laya_error` plus a specific class
#' `laya_error_<kind>`, so you can handle one kind of failure on its own, for
#' example `tryCatch(..., laya_error_no_markers = function(e) ...)`. The kind
#' is also stored in the condition's `kind` field. Warnings from the engine
#' (for example a long-document window being capped) have class
#' `laya_warning`.
#'
#' Kinds from the engine: `io`, `json`, `artifacts_not_found`,
#' `directory_not_found`, `missing_file`, `download`, `tokenizer`, `onnx`,
#' `invalid_question`, `invalid_config`, `checkpoint_mismatch`, `no_markers`,
#' `invalid_state`, `unsupported_aggregate`, `invalid_window`,
#' `not_supported`, `invalid_min_confidence`. Kinds from layaR itself:
#' `model_not_found`, `model_not_published`, `model_exists`,
#' `runtime_not_found`, `runtime_load`,
#' `invalid_argument`, `forked`, `bridge_json`, `bridge_invalid_option`,
#' `bridge_engine_closed`, `bridge_panic`. Model downloads and imports also
#' use the engine's `download`, `io` and `artifacts_not_found`.
#'
#' @name laya_conditions
#' @keywords internal
NULL

laya_abort <- function(message, kind, ..., call = parent.frame(), .envir = parent.frame()) {
  cli::cli_abort(
    message,
    class = c(paste0("laya_error_", kind), "laya_error"),
    kind = kind,
    ...,
    call = call,
    .envir = .envir
  )
}

# Base-R stand-in for rlang::check_dots_empty(): a misspelled argument fails
# instead of being swallowed by `...`.
check_dots_empty <- function(..., call = parent.frame()) {
  n <- ...length()
  if (n) {
    nms <- names(list(...))
    shown <- if (is.null(nms)) rep("", n) else nms
    shown[shown == ""] <- "<unnamed>"
    laya_abort(c("Unexpected argument{?s}: {.arg {shown}}.",
                 i = "Check the spelling; options are named arguments after {.arg ...}."),
               kind = "invalid_argument", call = call)
  }
}
