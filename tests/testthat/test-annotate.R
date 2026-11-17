qs <- laya_questions(
  department = laya_choice("Which department should handle this request?",
                           billing = "invoices, payments, refunds",
                           technical = "bugs, outages, system errors",
                           other = "everything else"),
  urgency = laya_score("How urgent is this request?", c("not urgent", "soon", "blocking")),
  churn_risk = laya_noul("Does the user threaten to cancel or leave?")
)

tickets <- data.frame(
  id = 1:4,
  subject = c("Duplicate charge", "App crashes", NA, "Pricing"),
  body = c("We were billed twice. Refund it now or we cancel.", "The app crashes on login.",
           NA, "What does the Pro plan cost?"),
  stringsAsFactors = FALSE
)

test_that("laya_annotate checks its arguments before predicting", {
  eng <- structure(new.env(), class = "laya_engine")
  expect_error(laya_annotate(list(a = 1), qs, "a", engine = eng), class = "laya_error_invalid_argument")
  expect_error(laya_annotate(tickets, qs, engine = eng), class = "laya_error_invalid_argument")
  expect_error(laya_annotate(tickets, qs, "nope", engine = eng), "nope")
  clash <- transform(tickets, urgency = 1)
  expect_error(laya_annotate(clash, qs, "body", engine = eng), "prefix")
})

test_that("laya_annotate adds typed answer columns", {
  skip_if_not(laya_model_available("multilingual"), "no local multilingual model")
  out <- laya_annotate(tickets, qs, state = c("subject", "body"), progress = FALSE)
  expect_identical(names(out), c(names(tickets), "department", "department_confidence",
                                 "urgency", "urgency_confidence", "churn_risk", "churn_risk_confidence"))
  expect_s3_class(out$department, "factor")
  expect_identical(levels(out$department), c("billing", "technical", "other"))
  expect_identical(as.character(out$department[1:2]), c("billing", "technical"))
  expect_true(is.na(out$department[[3]]) && is.na(out$churn_risk[[3]]))
  expect_true(all(out$urgency[-3] >= 0 & out$urgency[-3] <= 2))
  expect_true(all(out$churn_risk[-3] >= 0 & out$churn_risk[-3] <= 1))

  # One column: its text is the state; probabilities and gating add columns.
  one <- laya_annotate(tickets[-3, ], qs["churn_risk"], state = "body", prefix = "laya_",
                       confidence = FALSE, probabilities = TRUE, min_confidence = 0.99,
                       progress = FALSE)
  expect_identical(setdiff(names(one), names(tickets)),
                   c("laya_churn_risk", "laya_churn_risk_abstained", "laya_churn_risk_probabilities"))
  expect_named(one$laya_churn_risk_probabilities[[1]], c("false", "true"))
  expect_type(one$laya_churn_risk_abstained, "logical")

  skip_if_not_installed("tibble")
  tb <- laya_annotate(tibble::as_tibble(tickets[1:2, ]), qs["department"], "body", progress = FALSE)
  expect_s3_class(tb, "tbl_df")
})
