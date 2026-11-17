# Edge cases and engine lifecycle (plan Phase 4).

test_that("numbers follow Python's int/float split", {
  # The engine re-serializes structured states the way Python's json.dumps
  # does, so the text the model reads depends on these rules.
  expect_identical(as.character(to_json(list(mrr = 149, tickets = 3L))), '{"mrr":149.0,"tickets":3}')
  # Doubles reach the engine bit-for-bit.
  third <- from_json(as.character(to_json(list(x = 1 / 3))))$x
  expect_identical(third, 1 / 3)
  expect_identical(as.character(to_json(list(a = NA, b = NULL, c = TRUE))), '{"a":null,"b":null,"c":true}')
  expect_identical(as.character(to_json(list(), empty_object = TRUE)), "{}")
  expect_identical(as.character(to_json(list(), array = TRUE)), "[]")
})

test_that("non-ASCII question ids and labels survive the bridge", {
  qs <- laya_questions(
    "القسم" = laya_choice("ما هو القسم المناسب؟", "الفواتير" = "المدفوعات", "الدعم" = "الأعطال"),
    "紧急" = laya_score("有多紧急?", c("低", "高"))
  )
  back <- as_laya_questions(laya_questions_to_json(qs))
  expect_identical(names(back), names(qs))
  expect_identical(names(back[[1]]$criteria), c("الفواتير", "الدعم"))
  expect_identical(laya_validate_questions(qs), qs)
})

test_that("engines refuse to run in a forked child", {
  skip_on_os("windows")
  # A stand-in engine: the guard runs before any Rust code, so no model is needed.
  eng <- structure(new.env(), class = "laya_engine")
  eng$closed <- FALSE
  eng$pid <- Sys.getpid()
  eng$ptr <- NULL
  # In this process an engine without a live pointer just needs reconnecting.
  expect_silent(check_not_forked(eng))

  skip_if_no_model <- !laya_model_available("multilingual")
  if (skip_if_no_model) skip("no local multilingual model")
  real <- laya_engine("multilingual", intra_op_threads = 1)
  on.exit(laya_engine_close(real))
  child <- parallel::mcparallel(tryCatch(
    laya_predict("I want a refund", laya_questions(r = laya_noul("Refund?")), engine = real),
    laya_error_forked = function(e) "refused"
  ))
  expect_identical(parallel::mccollect(child, wait = TRUE)[[1]], "refused")
  # The parent's engine still works.
  res <- laya_predict("I want a refund", laya_questions(r = laya_noul("Refund?")), engine = real)
  expect_s3_class(res, "laya_result")
})

test_that("engines are freed by garbage collection without crashing", {
  skip_if_not(laya_model_available("multilingual"), "no local multilingual model")
  eng <- laya_engine("multilingual", intra_op_threads = 1)
  rm(eng)
  gc()
  gc()
  # A second engine loads fine after the first was collected.
  eng2 <- laya_engine("multilingual", intra_op_threads = 1)
  expect_true(rs_engine_is_live(eng2$ptr))
  laya_engine_close(eng2)
  expect_false(rs_engine_is_live(eng2$ptr))
  # Closing twice is harmless.
  expect_no_error(laya_engine_close(eng2))
})
