# Unwrapping the bridge envelope (plan D4, D5).
#
# Every `rs_*` call (except the plain predicates) returns
# list(ok, value, error_kind, error_message, warnings). Warnings are replayed as
# `laya_warning` conditions; errors become `laya_error_<kind>` conditions, so
# callers can catch one kind specifically:
#   tryCatch(..., laya_error_no_markers = function(e) ...)

rs_unwrap <- function(res, call = rlang_caller_env()) {
  for (w in res$warnings) {
    cli::cli_warn("{w}", class = "laya_warning")
  }
  if (!isTRUE(res$ok)) {
    laya_abort(res$error_message, kind = res$error_kind, call = call)
  }
  res$value
}

laya_abort <- function(message, kind, ..., call = rlang_caller_env()) {
  cli::cli_abort(
    "{message}",
    class = c(paste0("laya_error_", kind), "laya_error"),
    kind = kind,
    ...,
    call = call,
    .envir = environment()
  )
}

# The calling function's frame, without importing rlang: two frames up from
# here is the user-facing function that called `rs_unwrap()`.
rlang_caller_env <- function(n = 2) {
  parent.frame(n + 1)
}
