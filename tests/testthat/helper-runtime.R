# Model-backed tests also need ONNX Runtime. With LAYAR_TEST_RUNTIME=true
# (set in CI) the tests download it when it's missing and a failure to load
# it fails the test; otherwise they use an installed one, or skip.
runtime_state <- local({
  state <- NULL
  function() {
    if (is.null(state)) {
      state <<- tryCatch({
        if (runtime_required() && needs_runtime()) laya_install_runtime(ask = FALSE)
        if (is.null(rs_runtime_loaded()) && is.null(runtime_resolve())) {
          list(ok = FALSE, why = "ONNX Runtime not installed")
        } else {
          ensure_runtime()
          list(ok = TRUE, why = NULL)
        }
      }, laya_error = function(e) list(ok = FALSE, why = conditionMessage(e)))
    }
    state
  }
})

runtime_required <- function() identical(Sys.getenv("LAYAR_TEST_RUNTIME"), "true")

skip_without_runtime <- function() {
  st <- runtime_state()
  if (!st$ok && runtime_required()) testthat::fail(paste("ONNX Runtime didn't load:", st$why))
  skip_if_not(st$ok, st$why)
}
