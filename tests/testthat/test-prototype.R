test_that("a missing model directory is an R error, not a crash", {
  expect_error(proto_engine(tempfile("no-model-")), "does not exist|not found|Missing", ignore.case = TRUE)
})

test_that("prototype predicts with a local model", {
  dir <- file.path(tools::R_user_dir("layaR", "cache"), "onnx", "multilingual")
  skip_if_not(dir.exists(dir), "no local multilingual model")
  eng <- proto_engine(dir)
  res <- proto_predict(eng, "We were billed twice for March. Please refund.", list(
    department = list(type = "choice", instructions = "Which department?",
                      criteria = list(billing = "payments, refunds", technical = "bugs"))
  ))
  expect_identical(res$answers$department$choice, "billing")
})
