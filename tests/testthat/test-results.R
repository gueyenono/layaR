# Result handling, from a canned result in the bridge's JSON shape (no model).

canned <- function() {
  new_laya_result(from_json('{
    "model": "laya-rl-agent",
    "answers": {
      "department": {"type": "choice", "choice": "billing",
        "probabilities": {"billing": 0.83, "other": 0.17},
        "confidence": 0.34, "answer_confidence": 0.83, "action": {"act_probability": 1.0}},
      "urgency": {"type": "score", "score": 1.5, "legend": {"0": "low", "1": "mid", "2": "high"},
        "probabilities": {"0": 0.1, "1": 0.3, "2": 0.6},
        "confidence": 0.2, "answer_confidence": 0.6, "action": {"act_probability": 0.9},
        "abstention": "abstained", "abstention_threshold": 0.5},
      "churn": {"type": "noul", "noul": 0.0097,
        "confidence": 0.99, "answer_confidence": 0.99, "action": {"act_probability": 1.0}}
    },
    "usage": {"input_tokens": 142, "output_tokens": 0, "state_tokens": 32,
              "state_tokens_dropped": 0, "truncated": false, "truncated_questions": []}
  }'))
}

test_that("results keep the Python shape and gain classes", {
  res <- canned()
  expect_s3_class(res, "laya_result")
  expect_identical(res$answers$department$choice, "billing")
  expect_s3_class(res$answers$urgency, c("laya_answer_score", "laya_answer"))
  expect_identical(laya_answer(res, "churn")$noul, 0.0097)
  expect_error(laya_answer(res, "nope"), class = "laya_error_invalid_argument")
})

test_that("as.data.frame gives one row per question", {
  df <- as.data.frame(canned())
  expect_identical(df$id, c("department", "urgency", "churn"))
  expect_identical(df$answer, c("billing", "1.50", "FALSE"))
  expect_equal(df$value, c(0.83, 1.5, 0.0097))
  expect_identical(df$abstention, c(NA, "abstained", NA))
  expect_named(df, c("id", "type", "answer", "value", "confidence", "answer_confidence",
                     "act_probability", "abstention"))
})

test_that("laya_probabilities gives one row per option", {
  p <- laya_probabilities(canned())
  expect_identical(p$option, c("billing", "other", "low", "mid", "high", "false", "true"))
  expect_equal(p$probability[6:7], c(1 - 0.0097, 0.0097))
})

test_that("results print", {
  expect_output(print(canned()), "<laya_result> laya-rl-agent")
  expect_output(print(canned()), "\\[abstained\\]")
  expect_output(print(canned()$answers$department), "choice: billing")
})

test_that("batch results stack with a state_id", {
  b <- structure(list(canned(), canned()), class = "laya_batch_result")
  df <- as.data.frame(b)
  expect_identical(nrow(df), 6L)
  expect_identical(df$state_id, rep(1:2, each = 3))
  expect_identical(nrow(laya_probabilities(b)), 14L)
  expect_s3_class(b[2], "laya_batch_result")
  expect_output(print(b), "2 states")
  empty <- structure(list(), class = "laya_batch_result")
  expect_identical(nrow(as.data.frame(empty)), 0L)
})
