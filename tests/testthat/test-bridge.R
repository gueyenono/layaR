# Tests of the Rust bridge (rs_* functions) through the envelope.

call_rs <- function(res) rs_unwrap(res, call = NULL)

qs_json <- function(x) as.character(to_json(x))

triage_qs <- list(
  department = list(
    type = "choice", instructions = "Which department should handle this request?",
    criteria = list(billing = "invoices, payments, refunds", technical = "bugs, outages")
  ),
  urgency = list(
    type = "score", instructions = "How urgent is this request?",
    criteria = list("not urgent", "soon", "blocking")
  ),
  churn_risk = list(type = "noul", instructions = "Does the user threaten to cancel?")
)

# ---- model-free -------------------------------------------------------------

test_that("the envelope has the documented shape", {
  res <- rs_questions_validate(qs_json(triage_qs))
  expect_named(res, c("ok", "value", "error_kind", "error_message", "warnings"))
  expect_true(res$ok)
  expect_type(res$warnings, "character")
})

test_that("questions round-trip through validation in order", {
  out <- from_json(call_rs(rs_questions_validate(qs_json(triage_qs))))
  expect_named(out, names(triage_qs))
  expect_identical(out$department$criteria$billing, "invoices, payments, refunds")
  expect_null(out$churn_risk$criteria)
})

test_that("bridge errors become classed R conditions", {
  bad <- list(q = list(type = "maybe", instructions = "x"))
  expect_error(call_rs(rs_questions_validate(qs_json(bad))), class = "laya_error_invalid_question")
  expect_error(call_rs(rs_questions_validate("{oops")), class = "laya_error_bridge_json")
  labels <- list(q = list(type = "noul", instructions = "x", labels = list(false = "B", true = "A")))
  expect_error(call_rs(rs_questions_validate(qs_json(labels))), class = "laya_error_not_supported")
  # Every bridge error also carries the parent class and the kind.
  err <- tryCatch(call_rs(rs_questions_validate("{oops")), laya_error = identity)
  expect_s3_class(err, "laya_error")
  expect_identical(err$kind, "bridge_json")
})

test_that("presets come back in Python format", {
  triage <- from_json(call_rs(rs_preset("triage", "null")))
  expect_true(all(c("intent", "is_urgent", "frustration") %in% names(triage)))
  email <- from_json(call_rs(rs_preset("email", qs_json(list(orders = "shipping", returns = "refunds")))))
  expect_named(email$category$criteria, c("orders", "returns"))
  expect_error(call_rs(rs_preset("nope", "null")), class = "laya_error_bridge_invalid_option")
  expect_error(call_rs(rs_preset("guard", qs_json(list(a = "b")))), class = "laya_error_bridge_invalid_option")
})

test_that("plain helpers work without a model", {
  expect_length(rs_bucket_keys(), 12)
  expect_true("choice:3-5" %in% rs_bucket_keys())
  v <- rs_versions()
  expect_named(v, c("layaR_bridge", "laya_onnx", "laya_onnx_rev", "ort"))
  expect_false(rs_artifacts_complete(tempdir()))
  expect_false(rs_engine_is_live(NULL))
  expect_false(rs_engine_is_live("not a pointer"))
})

test_that("a missing model directory is a classed error", {
  res <- rs_engine_new(file.path(tempdir(), "no-such-model"), "{}")
  expect_false(res$ok)
  expect_match(res$error_kind, "directory_not_found|artifacts_not_found|missing_file")
  expect_error(call_rs(rs_engine_new(tempdir(), '{"bogus": 1}')), class = "laya_error_bridge_invalid_option")
})

# ---- with a local model -----------------------------------------------------

model_dir <- function() {
  file.path(tools::R_user_dir("layaR", "cache"), "onnx", "multilingual")
}

skip_without_model <- function() {
  skip_if_not(rs_artifacts_complete(model_dir()), "no local multilingual model")
  skip_without_runtime()
}

local_engine <- local({
  engine <- NULL
  function() {
    if (is.null(engine) || !rs_engine_is_live(engine)) {
      engine <<- call_rs(rs_engine_new(model_dir(), '{"intra_op_threads": 2}'))
    }
    engine
  }
})

test_that("engine info reports the checkpoint and budgets", {
  skip_without_model()
  info <- from_json(call_rs(rs_engine_info(local_engine())))
  expect_identical(info$layout, "fused")
  expect_gt(info$max_len, 0)
  expect_gt(info$head_max_len, 0)
})

test_that("predict returns the Python result shape", {
  skip_without_model()
  state <- qs_json(list(body = "We were billed twice for March. Refund it or we cancel."))
  res <- from_json(call_rs(rs_predict(local_engine(), state, qs_json(triage_qs), "{}")))
  expect_identical(res$model, "laya-rl-agent")
  expect_named(res$answers, names(triage_qs))
  expect_identical(res$answers$department$choice, "billing")
  expect_named(res$answers$urgency$legend, c("0", "1", "2"))
  expect_true(res$usage$input_tokens > 0)
  expect_null(res$answers$churn_risk$abstention)
})

test_that("min_confidence gates every answer", {
  skip_without_model()
  res <- from_json(call_rs(rs_predict(
    local_engine(), qs_json("Refund please"), qs_json(triage_qs), '{"min_confidence": 0.99}'
  )))
  for (a in res$answers) {
    expect_true(a$abstention %in% c("passed", "abstained", "unevaluated"))
    expect_identical(a$abstention_threshold, 0.99)
  }
  expect_error(
    call_rs(rs_predict(local_engine(), qs_json("x"), qs_json(triage_qs), '{"min_confidence": 1.5}')),
    class = "laya_error_invalid_min_confidence"
  )
})

test_that("batch keeps input order and long scans report windows", {
  skip_without_model()
  states <- qs_json(list("I want a refund", "The app crashes on login"))
  out <- from_json(call_rs(rs_predict_batch(local_engine(), states, qs_json(triage_qs), '{"batch_size": 1}')))
  expect_length(out, 2)
  expect_identical(out[[1]]$answers$department$choice, "billing")
  expect_identical(out[[2]]$answers$department$choice, "technical")

  long <- paste(rep("Normal account activity.", 400), collapse = " ")
  long <- paste(long, "I was billed twice and want a refund today.")
  res <- from_json(call_rs(rs_predict_long(local_engine(), qs_json(long), qs_json(triage_qs), '{"window": 256}')))
  expect_gt(res$usage$windows, 1)
  expect_named(res$answers$department$window, c("index", "token_start", "token_end", "count"))
})

test_that("a null state and impossible budgets are classed errors", {
  skip_without_model()
  expect_error(
    call_rs(rs_predict(local_engine(), "null", qs_json(triage_qs), "{}")),
    class = "laya_error_invalid_state"
  )
  expect_error(
    call_rs(rs_predict(local_engine(), qs_json("x"), qs_json(triage_qs), '{"max_len": 8}')),
    class = "laya_error_no_markers"
  )
})

test_that("closed and deserialized engines fail cleanly", {
  skip_without_model()
  engine <- call_rs(rs_engine_new(model_dir(), "{}"))
  path <- tempfile(fileext = ".rds")
  saveRDS(engine, path)
  stale <- readRDS(path)
  expect_false(rs_engine_is_live(stale))
  expect_error(
    call_rs(rs_predict(stale, qs_json("x"), qs_json(triage_qs), "{}")),
    class = "laya_error_bridge_engine_closed"
  )
  call_rs(rs_engine_close(engine))
  call_rs(rs_engine_close(engine)) # idempotent
  expect_false(rs_engine_is_live(engine))
  expect_error(call_rs(rs_engine_info(engine)), class = "laya_error_bridge_engine_closed")
})
