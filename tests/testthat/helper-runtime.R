# Model-backed tests also need ONNX Runtime. With LAYAR_TEST_RUNTIME=true
# (set in CI) the tests download it when it's missing; otherwise they use an
# installed one, or skip.
runtime_ready <- local({
  ready <- NULL
  function() {
    if (is.null(ready)) {
      if (identical(Sys.getenv("LAYAR_TEST_RUNTIME"), "true") && needs_runtime()) {
        laya_install_runtime(ask = FALSE)
      }
      ready <<- !is.null(rs_runtime_loaded()) ||
        (!is.null(runtime_resolve()) &&
           tryCatch({ ensure_runtime(); TRUE }, laya_error = function(e) FALSE))
    }
    ready
  }
})

skip_without_runtime <- function() {
  skip_if_not(runtime_ready(), "ONNX Runtime not installed")
}
