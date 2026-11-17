# Text utilities against the Python SDK's recorded probes (no model needed).

test_that("laya_clean_email matches Python on every probe", {
  probe <- jsonlite::fromJSON(test_path("fixtures", "text", "email.json"), simplifyVector = FALSE)
  bodies <- vapply(probe$clean, `[[`, "", "body")
  want <- vapply(probe$clean, `[[`, "", "result")
  budgets <- vapply(probe$clean, function(case) as.numeric(case$max_chars), numeric(1))
  got <- vapply(seq_along(bodies), function(i) laya_clean_email(bodies[[i]], budgets[[i]]), "")
  bad <- which(got != want)
  expect(!length(bad), paste("differs from Python:",
                             toString(vapply(probe$clean[bad], `[[`, "", "label"))))
  expect_gt(length(bodies), 200)
})

test_that("laya_email_state matches Python on every probe", {
  probe <- jsonlite::fromJSON(test_path("fixtures", "text", "email.json"), simplifyVector = FALSE)
  for (case in probe$state) {
    extra <- case$extra
    max_chars <- extra$max_chars %||% 3000
    extra$max_chars <- NULL
    got <- do.call(laya_email_state, c(
      list(subject = case$subject %||% "", body = case$body %||% "", sender = case$sender,
           clean = case$clean, max_chars = max_chars),
      extra
    ))
    expect_identical(got, case$result, label = case$label)
  }
})

test_that("laya_detect_language matches Python on every probe", {
  probe <- jsonlite::fromJSON(test_path("fixtures", "text", "lang.json"), simplifyVector = FALSE)
  states <- lapply(probe, `[[`, "state")
  got <- from_json(rs_unwrap(rs_detect_language(as.character(to_json(states, array = TRUE)))))
  fields <- c("script", "language", "is_english", "language_undecided", "mixed_segment")
  for (i in seq_along(probe)) {
    want <- probe[[i]]$analyse
    for (f in fields) {
      expect_identical(got[[i]][[f]], want[[f]], label = paste(probe[[i]]$label, f))
    }
    expect_equal(got[[i]]$diacritic_rate, want$diacritic_rate, tolerance = 1e-4,
                 label = paste(probe[[i]]$label, "diacritic_rate"))
    expect_equal(got[[i]]$non_latin_fraction, want$non_latin_fraction, tolerance = 1e-4,
                 label = paste(probe[[i]]$label, "non_latin_fraction"))
  }
})

test_that("laya_detect_language takes texts, one state, lists and data frames", {
  out <- laya_detect_language(c("Please refund the duplicate charge", "glömt lösenord"))
  expect_s3_class(out, "data.frame")
  expect_identical(out$is_english, c(TRUE, FALSE))
  expect_identical(out$language[[2]], "sv")
  expect_named(out$script_profile[[1]], "latin")

  one <- laya_detect_language(list(subject = "Refund", body = "Hola, me cobraron dos veces. \u00bfPueden devolverme el dinero?"))
  expect_identical(nrow(one), 1L)
  expect_false(one$is_english)

  df <- data.frame(subject = c("Refund", "Bug"), body = c("Charged twice", "App crashes"))
  expect_identical(nrow(laya_detect_language(df)), 2L)
  expect_error(laya_detect_language(c("a", NA)), class = "laya_error_invalid_state")
})

test_that("email helpers check their arguments", {
  expect_identical(laya_clean_email(c(a = "Hi", b = NA)), c(a = "Hi", b = NA))
  expect_identical(laya_clean_email(character()), character())
  expect_identical(laya_clean_email("Hello there", 0), "")
  expect_error(laya_clean_email(1), class = "laya_error_invalid_argument")
  expect_error(laya_clean_email("x", 1.5), class = "laya_error_invalid_argument")
  expect_named(laya_email_state("S", "B", ticket = 1L, note = NULL), c("subject", "body", "ticket"))
  expect_error(laya_email_state("S", "B", 1L), class = "laya_error_invalid_argument")
  expect_error(laya_email_state(c("a", "b"), "B"), class = "laya_error_invalid_argument")
})
