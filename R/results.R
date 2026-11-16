# Results (plan 7.5). A laya_result keeps the Python SDK's result shape
# (model, answers, usage), so `res$answers$department$choice` works as in
# Python, and adds printing and data-frame conversion.

#' Laya results
#'
#' A `laya_result` is a list with `model`, `answers` (one entry per question,
#' in question order) and `usage` (token accounting and truncation flags),
#' in the Python SDK's shape. Each answer has `type`, `confidence`,
#' `answer_confidence` and `action$act_probability`, plus:
#'
#' * choice: `choice` (the top label) and `probabilities` (per label);
#' * score: `score` (the expected level, from 0 to levels - 1), `legend` and
#'   `probabilities` (per level, keyed `"0"`, `"1"`, ...);
#' * noul: `noul` (the probability the statement holds).
#'
#' With `min_confidence`, answers also carry `abstention` and
#' `abstention_threshold`; from [laya_predict_long()], `window`.
#'
#' `as.data.frame()` gives one row per question; `laya_probabilities()` one
#' row per option; `laya_answer()` extracts one answer. A
#' `laya_batch_result` (from [laya_predict_batch()]) is a list of
#' `laya_result`s whose data-frame forms carry a `state_id` column.
#'
#' @param x A `laya_result` or `laya_batch_result`.
#' @param row.names,optional Ignored; part of the [as.data.frame()] generic.
#' @param ... Unused.
#' @return `as.data.frame()` returns a data frame with columns `id`, `type`,
#'   `answer` (the label, the score or `TRUE`/`FALSE`, as text), `value` (the
#'   chosen label's probability, the score, or P(true)), `confidence`,
#'   `answer_confidence`, `act_probability` and `abstention`.
#'   `laya_probabilities()` returns columns `id`, `type`, `option` and
#'   `probability` (for noul questions, options `"false"` and `"true"`).
#' @examples
#' if (laya_model_available()) {
#'   res <- laya_predict("Refund me now!", laya_preset("triage"))
#'   as.data.frame(res)
#'   laya_probabilities(res)
#'   laya_answer(res, "intent")$choice
#' }
#' @name laya_result
NULL

new_laya_result <- function(x) {
  for (id in names(x$answers)) {
    a <- x$answers[[id]]
    class(a) <- c(paste0("laya_answer_", a$type), "laya_answer")
    x$answers[[id]] <- a
  }
  if (is.null(x$answers)) x$answers <- structure(list(), names = character())
  structure(x, class = "laya_result")
}

# One-line summary values for an answer.
answer_parts <- function(a) {
  switch(
    a$type,
    choice = list(answer = a$choice, value = a$probabilities[[a$choice]]),
    score = list(answer = format(round(a$score, 2), nsmall = 2), value = a$score),
    noul = list(answer = if (a$noul >= 0.5) "TRUE" else "FALSE", value = a$noul),
    list(answer = NA_character_, value = NA_real_)
  )
}

#' @rdname laya_result
#' @export
as.data.frame.laya_result <- function(x, row.names = NULL, optional = FALSE, ...) {
  ids <- names(x$answers)
  rows <- lapply(ids, function(id) {
    a <- x$answers[[id]]
    p <- answer_parts(a)
    data.frame(
      id = id,
      type = a$type,
      answer = p$answer,
      value = as.numeric(p$value),
      confidence = as.numeric(a$confidence),
      answer_confidence = as.numeric(a$answer_confidence),
      act_probability = as.numeric(a$action$act_probability %||% NA_real_),
      abstention = a$abstention %||% NA_character_,
      stringsAsFactors = FALSE
    )
  })
  if (!length(rows)) return(empty_answers_df())
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

empty_answers_df <- function() {
  data.frame(id = character(), type = character(), answer = character(), value = numeric(),
             confidence = numeric(), answer_confidence = numeric(), act_probability = numeric(),
             abstention = character(), stringsAsFactors = FALSE)
}

#' @rdname laya_result
#' @export
laya_probabilities <- function(x) {
  UseMethod("laya_probabilities")
}

#' @export
laya_probabilities.laya_result <- function(x) {
  rows <- lapply(names(x$answers), function(id) {
    a <- x$answers[[id]]
    switch(
      a$type,
      choice = data.frame(id = id, type = "choice", option = names(a$probabilities),
                          probability = as.numeric(unlist(a$probabilities)), stringsAsFactors = FALSE),
      score = {
        lv <- vapply(a$legend, function(l) if (is.character(l)) l else as.character(to_json(l)), character(1))
        data.frame(id = id, type = "score", option = unname(lv),
                   probability = as.numeric(unlist(a$probabilities)), stringsAsFactors = FALSE)
      },
      noul = data.frame(id = id, type = "noul", option = c("false", "true"),
                        probability = c(1 - a$noul, a$noul), stringsAsFactors = FALSE)
    )
  })
  if (!length(rows)) {
    return(data.frame(id = character(), type = character(), option = character(),
                      probability = numeric(), stringsAsFactors = FALSE))
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

#' @export
laya_probabilities.laya_batch_result <- function(x) {
  stack_with_state_id(x, laya_probabilities)
}

#' @rdname laya_result
#' @param id A question id.
#' @export
laya_answer <- function(x, id) {
  if (!inherits(x, "laya_result")) {
    laya_abort("{.arg x} must be a {.cls laya_result}.", kind = "invalid_argument")
  }
  a <- x$answers[[id]]
  if (is.null(a)) {
    laya_abort("No answer with id {.val {id}}; ids are {.val {names(x$answers)}}.",
               kind = "invalid_argument")
  }
  a
}

#' @export
format.laya_result <- function(x, ...) {
  n <- length(x$answers)
  head <- sprintf("<laya_result> %s \u00b7 %d answer%s \u00b7 %s input tokens",
                  x$model %||% "?", n, if (n == 1) "" else "s",
                  format(x$usage$input_tokens %||% NA))
  if (isTRUE(as.logical(x$usage$truncated))) head <- paste0(head, " \u00b7 state truncated")
  if (!is.null(x$usage$windows)) head <- paste0(head, sprintf(" \u00b7 %d windows", x$usage$windows))
  if (!n) return(head)
  ids <- format(names(x$answers))
  lines <- vapply(seq_len(n), function(i) {
    a <- x$answers[[i]]
    detail <- switch(
      a$type,
      choice = sprintf("%-14s p %.2f", truncate_text(a$choice, 14), a$probabilities[[a$choice]]),
      score = sprintf("%-14s", sprintf("%.2f (0\u2013%d)", a$score, length(a$legend) - 1L)),
      noul = sprintf("%-14s", sprintf("%.2f \u2192 %s", a$noul, if (a$noul >= 0.5) "TRUE" else "FALSE")),
      ""
    )
    gate <- if (!is.null(a$abstention)) paste0("  [", a$abstention, "]") else ""
    sprintf("  %s  %-6s  %s  confidence %.2f%s", ids[[i]], a$type, detail, a$confidence, gate)
  }, character(1))
  c(head, lines)
}

#' @export
print.laya_result <- function(x, ...) {
  cat(format(x), sep = "\n")
  invisible(x)
}

#' @export
format.laya_answer <- function(x, ...) {
  p <- answer_parts(x)
  sprintf("<laya_answer> %s: %s (confidence %.2f)", x$type, p$answer, x$confidence)
}

#' @export
print.laya_answer <- function(x, ...) {
  cat(format(x), "\n", sep = "")
  invisible(x)
}

# ---- batch results ----

#' @rdname laya_result
#' @export
as.data.frame.laya_batch_result <- function(x, row.names = NULL, optional = FALSE, ...) {
  stack_with_state_id(x, as.data.frame)
}

stack_with_state_id <- function(x, f) {
  parts <- lapply(seq_along(x), function(i) {
    df <- f(x[[i]])
    if (nrow(df)) cbind(state_id = i, df) else NULL
  })
  parts <- parts[!vapply(parts, is.null, logical(1))]
  if (!length(parts)) {
    template <- f(new_laya_result(list(answers = list())))
    return(cbind(state_id = integer(), template))
  }
  out <- do.call(rbind, parts)
  rownames(out) <- NULL
  out
}

#' @export
`[.laya_batch_result` <- function(x, i) {
  structure(unclass(x)[i], class = "laya_batch_result")
}

#' @export
format.laya_batch_result <- function(x, ...) {
  n <- length(x)
  head <- sprintf("<laya_batch_result> %d state%s", n, if (n == 1) "" else "s")
  if (!n) return(head)
  ids <- names(x[[1]]$answers)
  tokens <- sum(vapply(x, function(r) as.numeric(r$usage$input_tokens %||% 0), numeric(1)))
  c(paste0(head, sprintf(" \u00b7 %d question%s \u00b7 %s input tokens",
                         length(ids), if (length(ids) == 1) "" else "s", format(tokens))),
    paste0("  questions: ", truncate_text(paste(ids, collapse = ", "), 70)),
    "  use as.data.frame() for one row per state and question")
}

#' @export
print.laya_batch_result <- function(x, ...) {
  cat(format(x), sep = "\n")
  invisible(x)
}
