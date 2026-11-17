# Phase 0 prototype. Replaced by the real API in Phase 3.

#' Prototype: load an engine and predict one state
#'
#' @param state A character string or a named list.
#' @param questions Questions in the Python dict format, as an R list.
#' @param model_dir Path to an exported checkpoint directory.
#' @param engine An engine from `proto_engine()`.
#' @return `proto_engine()` returns an external pointer; `proto_predict()`
#'   returns the parsed result as a list.
#' @keywords internal
#' @name prototype
NULL

#' @rdname prototype
#' @export
proto_engine <- function(model_dir) {
  rs_engine_new(path.expand(model_dir))
}

#' @rdname prototype
#' @export
proto_predict <- function(engine, state, questions) {
  enc <- function(x) jsonlite::toJSON(x, auto_unbox = TRUE, digits = NA, null = "null")
  out <- rs_predict(engine, enc(state), enc(questions))
  jsonlite::fromJSON(out, simplifyVector = FALSE)
}
