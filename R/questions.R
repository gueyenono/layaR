# Question constructors (plan 7.2). A question set is stored in Python's
# format, `{id: {type, instructions, criteria}}`, so it can be shared with the
# Python SDK and passed to the bridge unchanged.

#' Build Laya questions
#'
#' Laya answers three kinds of typed question about a state in one forward
#' pass:
#'
#' * `laya_choice()`: pick one label from a fixed set of options.
#' * `laya_score()`: place the state on an ordinal scale (levels lowest first);
#'   the answer is the expected level, a number between 0 and the number of
#'   levels minus one.
#' * `laya_noul()`: a yes/no statement; the answer is the calibrated
#'   probability that it holds.
#'
#' Combine questions into a set with [laya_questions()].
#'
#' @param instructions The question, as a string. A list is also accepted and
#'   is serialized to JSON, as the Python SDK does for structured instructions.
#' @param ... For `laya_choice()`, the options: either named arguments
#'   (`label = "description"`) or unnamed labels without descriptions. Option
#'   order matters: the model scores one marker per option, in order.
#' @param .options Alternatively, the options as a named character vector or
#'   list (labels with descriptions), or an unnamed character vector (labels
#'   only).
#' @param levels For `laya_score()`, the levels from lowest to highest, as a
#'   character vector or a list of structured levels.
#' @param if_false,if_true For `laya_noul()`, optional descriptions of what
#'   the false and true sides mean.
#' @return A `laya_question` object.
#' @seealso [laya_questions()], [laya_preset()]
#' @examples
#' laya_choice(
#'   "Which department should handle this request?",
#'   billing = "invoices, payments, refunds",
#'   technical = "bugs, outages, system errors",
#'   other = "everything else"
#' )
#' laya_choice("What is this about?", "coding", "writing", "other")
#' laya_score("How urgent is this request?", c("not urgent", "soon", "blocking"))
#' laya_noul("Is this email a phishing attempt?",
#'           if_false = "a legitimate email", if_true = "phishing or fraud")
#' @name laya_question
NULL

#' @rdname laya_question
#' @export
laya_choice <- function(instructions, ..., .options = NULL) {
  check_instructions(instructions)
  dots <- list(...)
  if (length(dots) && !is.null(.options)) {
    laya_abort("Give the options either in {.arg ...} or in {.arg .options}, not both.",
               kind = "invalid_question")
  }
  opts <- if (length(dots)) dots else .options
  if (!length(opts)) {
    laya_abort("A choice question needs at least one option.", kind = "invalid_question")
  }
  if (is.factor(opts)) opts <- as.character(opts)
  nms <- names(opts)
  criteria <- if (is.null(nms) || all(nms == "")) {
    labels <- vapply(opts, function(x) {
      if (!is_scalar_text(x)) {
        laya_abort("Unnamed choice options must be single strings (labels).", kind = "invalid_question")
      }
      as.character(x)
    }, character(1), USE.NAMES = FALSE)
    check_unique(labels, "choice label")
    as.list(labels)
  } else {
    if (any(nms == "")) {
      laya_abort("Choice options must be all named ({.code label = description}) or all unnamed (labels only).",
                 kind = "invalid_question")
    }
    check_unique(nms, "choice label")
    opts <- as.list(opts)
    for (i in seq_along(opts)) {
      d <- opts[[i]]
      if (is.null(d) || (length(d) == 1 && is.na(d))) opts[[i]] <- ""
      else if (is.factor(d)) opts[[i]] <- as.character(d)
    }
    opts
  }
  new_laya_question("choice", instructions, criteria)
}

#' @rdname laya_question
#' @export
laya_score <- function(instructions, levels) {
  check_instructions(instructions)
  if (missing(levels) || !length(levels)) {
    laya_abort("A score question needs at least one level.", kind = "invalid_question")
  }
  if (is.factor(levels)) levels <- as.character(levels)
  levels <- as.list(levels)
  if (any(vapply(levels, function(x) is.null(x) || (length(x) == 1 && is.na(x)), logical(1)))) {
    laya_abort("Score levels cannot be {.code NULL} or {.code NA}; describe every level.",
               kind = "invalid_question")
  }
  new_laya_question("score", instructions, unname(levels))
}

#' @rdname laya_question
#' @export
laya_noul <- function(instructions, if_false = NULL, if_true = NULL) {
  check_instructions(instructions)
  criteria <- list()
  if (!is.null(if_false)) criteria[["false"]] <- if_false
  if (!is.null(if_true)) criteria[["true"]] <- if_true
  new_laya_question("noul", instructions, if (length(criteria)) criteria else NULL)
}

new_laya_question <- function(type, instructions, criteria) {
  q <- list(type = type, instructions = instructions)
  if (!is.null(criteria)) q$criteria <- criteria
  structure(q, class = "laya_question")
}

#' Combine questions into a question set
#'
#' @param ... Named questions built with [laya_choice()], [laya_score()] or
#'   [laya_noul()]. The names are the question ids used in the results.
#' @return A `laya_questions` object: a named list of questions in the Python
#'   SDK's format.
#' @seealso [as_laya_questions()] to import a Python question set, and
#'   [laya_questions_to_json()] to export one.
#' @examples
#' qs <- laya_questions(
#'   department = laya_choice("Which department?", billing = "refunds", technical = "bugs"),
#'   urgency = laya_score("How urgent?", c("low", "high")),
#'   churn_risk = laya_noul("Does the user threaten to cancel?")
#' )
#' qs
#' @export
laya_questions <- function(...) {
  qs <- list(...)
  for (i in seq_along(qs)) {
    if (!inherits(qs[[i]], "laya_question")) {
      laya_abort("Every element of {.fn laya_questions} must be a question built with {.fn laya_choice}, {.fn laya_score} or {.fn laya_noul}.",
                 kind = "invalid_question")
    }
  }
  new_laya_questions(qs)
}

new_laya_questions <- function(qs) {
  ids <- names(qs)
  if (length(qs) && (is.null(ids) || any(is.na(ids) | ids == ""))) {
    laya_abort("Every question needs a name (its id), e.g. {.code laya_questions(urgency = laya_score(...))}.",
               kind = "invalid_question")
  }
  check_unique(ids, "question id")
  structure(qs, class = "laya_questions")
}

#' Convert to a question set
#'
#' Accepts a question set in the Python SDK's format, so question sets can be
#' shared between Python and R: an R list, a JSON string, or the path to a
#' `.json` file.
#'
#' @param x A `laya_questions` object, a named list in the Python format
#'   (`list(id = list(type = , instructions = , criteria = ))`), a JSON
#'   string, or a path to a JSON file.
#' @param ... Unused.
#' @return A `laya_questions` object.
#' @examples
#' as_laya_questions('{
#'   "urgency": {"type": "score", "instructions": "How urgent?",
#'               "criteria": ["low", "high"]}
#' }')
#' @export
as_laya_questions <- function(x, ...) {
  UseMethod("as_laya_questions")
}

#' @export
as_laya_questions.laya_questions <- function(x, ...) x

#' @export
as_laya_questions.character <- function(x, ...) {
  if (length(x) != 1 || is.na(x)) {
    laya_abort("{.arg x} must be a single JSON string or file path.", kind = "invalid_question")
  }
  json <- if (!grepl("^\\s*[{[]", x) && file.exists(x)) {
    paste(readLines(x, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  } else {
    x
  }
  parsed <- tryCatch(from_json(json), error = function(e) {
    msg <- conditionMessage(e)
    laya_abort(c("Could not parse the questions as JSON.", x = "{msg}"), kind = "bridge_json")
  })
  as_laya_questions(parsed)
}

#' @export
as_laya_questions.list <- function(x, ...) {
  qs <- lapply(x, function(q) {
    if (inherits(q, "laya_question")) return(q)
    if (!is.list(q) || is.null(q$type)) {
      laya_abort("Each question must be a list with at least {.field type} and {.field instructions}.",
                 kind = "invalid_question")
    }
    if (is.list(q$criteria) || is.null(q$criteria)) {
      structure(q, class = "laya_question")
    } else {
      # A plain vector of labels or levels: keep it an array in JSON.
      q$criteria <- as.list(q$criteria)
      structure(q, class = "laya_question")
    }
  })
  new_laya_questions(qs)
}

#' @export
as_laya_questions.default <- function(x, ...) {
  laya_abort("Can't convert a {.cls {class(x)[[1]]}} to questions.", kind = "invalid_question")
}

#' Validate a question set without a model
#'
#' Runs the Rust engine's own question validation, so errors surface before
#' a model is loaded.
#'
#' @param questions A `laya_questions` object, or anything
#'   [as_laya_questions()] accepts.
#' @return `questions` as a `laya_questions` object, invisibly. Errors with a
#'   `laya_error_invalid_question` (or `laya_error_not_supported`) condition.
#' @examples
#' laya_validate_questions(laya_questions(spam = laya_noul("Is this spam?")))
#' @export
laya_validate_questions <- function(questions) {
  questions <- as_laya_questions(questions)
  rs_unwrap(rs_questions_validate(questions_json(questions)))
  invisible(questions)
}

#' Write a question set as JSON
#'
#' The output is in the Python SDK's format.
#'
#' @param questions A `laya_questions` object.
#' @param path Optional file path. If given, the JSON is written there.
#' @param pretty Pretty-print the JSON?
#' @return The JSON string (invisibly when `path` is given).
#' @examples
#' laya_questions_to_json(laya_questions(spam = laya_noul("Is this spam?")))
#' @export
laya_questions_to_json <- function(questions, path = NULL, pretty = TRUE) {
  questions <- as_laya_questions(questions)
  json <- questions_json(questions)
  if (pretty) json <- jsonlite::prettify(json, indent = 2)
  json <- as.character(json)
  if (!is.null(path)) {
    writeLines(enc2utf8(json), path, useBytes = TRUE)
    return(invisible(json))
  }
  json
}

questions_json <- function(questions) {
  as.character(to_json(lapply(unclass(questions), unclass)))
}

#' @export
`[.laya_questions` <- function(x, i) {
  new_laya_questions(unclass(x)[i])
}

#' @export
c.laya_questions <- function(...) {
  parts <- lapply(list(...), function(x) unclass(as_laya_questions(x)))
  new_laya_questions(do.call(c, parts))
}

#' @export
format.laya_question <- function(x, ...) {
  crit <- x$criteria
  detail <- switch(
    x$type,
    choice = {
      labels <- if (is.null(names(crit))) unlist(crit) else names(crit)
      paste0(length(labels), " options: ", truncate_text(paste(labels, collapse = ", "), 40))
    },
    score = paste0(length(crit), " levels"),
    noul = "yes/no",
    ""
  )
  ins <- if (is.character(x$instructions)) x$instructions else as.character(to_json(x$instructions))
  sprintf("%-6s %s  [%s]", x$type, truncate_text(ins, 60), detail)
}

#' @export
print.laya_question <- function(x, ...) {
  cat("<laya_question> ", format(x), "\n", sep = "")
  invisible(x)
}

#' @export
print.laya_questions <- function(x, ...) {
  cat("<laya_questions> ", length(x), if (length(x) == 1) " question" else " questions", "\n", sep = "")
  if (length(x)) {
    ids <- format(names(x))
    for (i in seq_along(x)) cat("  ", ids[[i]], "  ", format(x[[i]]), "\n", sep = "")
  }
  invisible(x)
}

check_instructions <- function(instructions) {
  ok <- (is.character(instructions) && length(instructions) == 1 && !is.na(instructions)) ||
    is.list(instructions)
  if (!ok) {
    laya_abort("{.arg instructions} must be a single string (or a list for structured instructions).",
               kind = "invalid_question")
  }
}

check_unique <- function(x, what) {
  dup <- unique(x[duplicated(x)])
  if (length(dup)) {
    laya_abort("Duplicate {what}{?s}: {.val {dup}}.", kind = "invalid_question")
  }
}

is_scalar_text <- function(x) {
  (is.character(x) || is.numeric(x) || is.logical(x)) && length(x) == 1 && !is.na(x)
}

truncate_text <- function(x, n) {
  x <- gsub("\\s+", " ", x)
  if (nchar(x) > n) paste0(substr(x, 1, n - 1), "\u2026") else x
}
