test_that("constructors build the Python format", {
  q <- laya_choice("Which?", billing = "refunds", other = "")
  expect_s3_class(q, "laya_question")
  expect_identical(unclass(q), list(type = "choice", instructions = "Which?",
                                    criteria = list(billing = "refunds", other = "")))

  expect_identical(laya_choice("About?", "a", "b")$criteria, list("a", "b"))
  expect_identical(laya_choice("About?", .options = c(x = "1", y = "2"))$criteria, list(x = "1", y = "2"))
  expect_identical(laya_choice("About?", .options = c("x", "y"))$criteria, list("x", "y"))

  s <- laya_score("How urgent?", c("low", "high"))
  expect_identical(s$criteria, list("low", "high"))
  # A single level must stay a list, so it is still a JSON array.
  expect_match(questions_json(laya_questions(u = laya_score("x", "only"))), '"criteria":["only"]', fixed = TRUE)

  expect_null(laya_noul("Spam?")$criteria)
  expect_identical(laya_noul("Spam?", if_true = "spam")$criteria, list(true = "spam"))
})

test_that("constructors refuse bad input with classed errors", {
  expect_error(laya_choice("x"), class = "laya_error_invalid_question")
  expect_error(laya_choice("x", a = "1", "b"), class = "laya_error_invalid_question")
  expect_error(laya_choice("x", a = "1", a = "2"), class = "laya_error_invalid_question")
  expect_error(laya_choice("x", "a", .options = c("b")), class = "laya_error_invalid_question")
  expect_error(laya_score("x", character()), class = "laya_error_invalid_question")
  expect_error(laya_score("x", c("a", NA)), class = "laya_error_invalid_question")
  expect_error(laya_noul(NA_character_), class = "laya_error_invalid_question")
  expect_error(laya_questions(laya_noul("x")), class = "laya_error_invalid_question")
  expect_error(laya_questions(a = laya_noul("x"), a = laya_noul("y")), class = "laya_error_invalid_question")
  expect_error(laya_questions(a = list(type = "noul")), class = "laya_error_invalid_question")
})

test_that("question sets subset, combine, print and validate", {
  qs <- laya_questions(a = laya_noul("A?"), b = laya_score("B?", c("lo", "hi")))
  expect_s3_class(qs["b"], "laya_questions")
  expect_named(c(qs, laya_questions(c = laya_noul("C?"))), c("a", "b", "c"))
  expect_error(c(qs, qs), class = "laya_error_invalid_question")
  expect_output(print(qs), "<laya_questions> 2 questions")
  expect_identical(laya_validate_questions(qs), qs)
})

test_that("Python-format JSON round-trips", {
  qs <- laya_questions(
    dept = laya_choice("Which?", billing = "refunds", technical = "bugs"),
    urgency = laya_score("How urgent?", c("low", "high")),
    churn = laya_noul("Leaving?", if_false = "staying", if_true = "leaving")
  )
  json <- laya_questions_to_json(qs)
  back <- as_laya_questions(json)
  expect_identical(names(back), names(qs))
  expect_identical(questions_json(back), questions_json(qs))

  path <- withr::local_tempfile(fileext = ".json")
  laya_questions_to_json(qs, path)
  expect_identical(questions_json(as_laya_questions(path)), questions_json(qs))

  # A Python dict pasted as an R list, with plain vectors as criteria.
  py <- list(topic = list(type = "choice", instructions = "Topic?", criteria = c("a", "b")))
  expect_identical(as_laya_questions(py)$topic$criteria, list("a", "b"))
  expect_error(as_laya_questions("{nope"), class = "laya_error_bridge_json")
  expect_error(as_laya_questions(42), class = "laya_error_invalid_question")
})

test_that("validation catches what the engine would refuse", {
  bad <- list(q = list(type = "noul", instructions = "x", labels = list(false = "B", true = "A")))
  expect_error(laya_validate_questions(bad), class = "laya_error_not_supported")
  expect_error(laya_validate_questions(list(q = list(type = "nope", instructions = "x"))),
               class = "laya_error_invalid_question")
})

test_that("presets load", {
  triage <- laya_preset("triage")
  expect_s3_class(triage, "laya_questions")
  expect_true("intent" %in% names(triage))
  email <- laya_preset("email", categories = c(orders = "shipping", returns = "refunds"))
  expect_named(email$category$criteria, c("orders", "returns"))
  expect_error(laya_preset("email", categories = c("a", "b")), class = "laya_error_invalid_argument")
  expect_error(laya_preset("nope"))
  expect_identical(nrow(laya_preset_fields()), 5L)
})
