# User-facing prediction API. Model-backed tests skip without a local model.

qs <- laya_questions(
  department = laya_choice("Which department should handle this request?",
                           billing = "invoices, payments, refunds",
                           technical = "bugs, outages, system errors"),
  urgency = laya_score("How urgent is this request?", c("not urgent", "soon", "blocking")),
  churn_risk = laya_noul("Does the user threaten to cancel or leave?")
)

test_that("argument checks run before any model is needed", {
  eng <- structure(new.env(), class = "laya_engine")
  expect_error(laya_predict(NULL, qs, engine = eng), class = "laya_error_invalid_state")
  expect_error(laya_predict(c("a", "b"), qs, engine = eng), class = "laya_error_invalid_argument")
  expect_error(laya_predict(NA_character_, qs, engine = eng), class = "laya_error_invalid_state")
  expect_error(laya_predict("a", qs, engine = eng, min_confidance = 0.5), class = "laya_error_invalid_argument")
  expect_error(laya_predict("a", qs, engine = eng, min_confidence = c(0.1, 0.2)), class = "laya_error_invalid_argument")
  expect_error(laya_predict_batch(c("a", NA), qs, engine = eng), class = "laya_error_invalid_state")
  expect_error(laya_predict_batch(list("a", NULL), qs, engine = eng), class = "laya_error_invalid_state")
  expect_error(laya_predict("a", qs, engine = "nope"), class = "laya_error_invalid_argument")
})

test_that("a missing model gives a helpful classed error", {
  withr::local_options(layaR.model_root = withr::local_tempdir(), layaR.shared_cache = FALSE)
  expect_false(laya_model_available())
  expect_error(laya_engine("english"), class = "laya_error_model_not_found")
})

test_that("model root follows the option, then LAYA_ONNX_ROOT", {
  withr::local_options(layaR.model_root = NULL)
  withr::local_envvar(LAYA_ONNX_ROOT = "/opt/laya-models")
  # normalizePath() adds a drive letter on Windows.
  expect_identical(laya_model_path("english"),
                   file.path(normalizePath("/opt/laya-models", mustWork = FALSE), "english"))
  withr::local_options(layaR.model_root = "/srv/models")
  expect_identical(laya_model_root(), normalizePath("/srv/models", mustWork = FALSE))
})

skip_if_no_model <- function() {
  skip_if_not(laya_model_available("multilingual"), "no local multilingual model")
  skip_without_runtime()
}

test_that("laya_predict answers every question", {
  skip_if_no_model()
  state <- list(subject = "Duplicate charge", body = "We were billed twice. Refund it or we cancel.")
  res <- laya_predict(state, qs)
  expect_s3_class(res, "laya_result")
  expect_identical(res$answers$department$choice, "billing")
  df <- as.data.frame(res)
  expect_identical(df$id, names(qs))
  expect_true(all(df$confidence >= 0 & df$confidence <= 1))
  # A one-row data frame is the same state.
  res_df <- laya_predict(as.data.frame(state), qs)
  expect_equal(res_df$answers$department$probabilities, res$answers$department$probabilities)
})

test_that("options reach the engine", {
  skip_if_no_model()
  gated <- laya_predict("Refund please", qs, min_confidence = 0.99)
  expect_true(all(!is.na(as.data.frame(gated)$abstention)))
  buckets <- laya_predict("Refund please", qs, min_confidence = c(default = 0.5, "noul:2" = 0.9))
  expect_identical(buckets$answers$churn_risk$abstention_threshold, 0.9)
  expect_error(laya_predict("x", qs, max_len = 8), class = "laya_error_no_markers")
  expect_error(laya_predict("x", qs, min_confidence = 2), class = "laya_error_invalid_min_confidence")
})

test_that("batches keep order across chunks", {
  skip_if_no_model()
  states <- c("Refund my duplicate charge", "The login page crashes", "Refund me now")
  b <- laya_predict_batch(states, qs, chunk_size = 2, progress = FALSE)
  expect_s3_class(b, "laya_batch_result")
  expect_length(b, 3)
  one <- laya_predict(states[[2]], qs)
  expect_equal(b[[2]]$answers$department$probabilities, one$answers$department$probabilities,
               tolerance = 1e-4)
  df <- data.frame(subject = c("Billing", "Bug"), body = c("Charged twice", "App crashes"))
  expect_length(laya_predict_batch(df, qs, progress = FALSE), 2)
  expect_length(laya_predict_batch(character(), qs), 0)
})

test_that("long documents are scanned in windows", {
  skip_if_no_model()
  long <- paste(c(rep("Normal account activity.", 400), "I was billed twice and want a refund."),
                collapse = " ")
  res <- laya_predict_long(long, qs, window = 256)
  expect_gt(res$usage$windows, 1)
  expect_false(is.null(res$answers$department$window))
})

test_that("engines print, report info, close, and survive saveRDS", {
  skip_if_no_model()
  eng <- laya_engine("multilingual", intra_op_threads = 1)
  expect_output(print(eng), "<laya_engine> multilingual")
  expect_identical(laya_engine_info(eng)$layout, "fused")
  expect_identical(laya_engine_info(eng)$checkpoint, "multilingual")

  path <- withr::local_tempfile(fileext = ".rds")
  saveRDS(eng, path)
  restored <- readRDS(path)
  expect_message(res <- laya_predict("I want a refund", qs, engine = restored),
                 class = "laya_reconnect")
  expect_identical(res$answers$department$choice, "billing")
  expect_identical(predict(restored, "The app crashes", qs)$answers$department$choice, "technical")

  laya_engine_close(eng)
  expect_error(laya_predict("x", qs, engine = eng), class = "laya_error_bridge_engine_closed")
  laya_engine_close(restored)
})
