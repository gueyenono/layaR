# Package-level state: cached default engines.
the <- new.env(parent = emptyenv())
the$engines <- list()

# predict.laya_engine() is registered on stats::predict.
#' @importFrom stats predict
NULL
