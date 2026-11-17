# laya_annotate() (plan 7.6): one prediction per data-frame row, answers
# added as columns.

#' Annotate a data frame
#'
#' Asks the same questions about every row of a data frame and adds the
#' answers as new columns, one or more per question:
#'
#' * a choice question gives a factor whose levels are the options, in order;
#' * a score question gives the expected level (a number from 0 to the
#'   number of levels minus one);
#' * a yes/no question gives the probability that the statement is true.
#'
#' With `confidence = TRUE` each answer also gets a `<id>_confidence` column.
#' With `min_confidence` (passed in `...`), each gated answer also gets a
#' logical `<id>_abstained` column. The answer is kept either way; filter on
#' the column to drop low-confidence answers. The gate compares the threshold
#' with each answer's `answer_confidence` (for a choice question, the chosen
#' option's probability), which can differ from the `<id>_confidence` column.
#'
#' @param data A data frame or tibble. A tibble stays a tibble.
#' @param questions A question set ([laya_questions()], a preset, or anything
#'   [as_laya_questions()] accepts).
#' @param state The name or names of the column(s) the model reads, as strings
#'   (`"text"`, `c("subject", "body")`), not bare names. With one column, its
#'   text is the state as is. With several, each row becomes a structured
#'   state such as `{"subject": ..., "body": ...}`, which keeps the field
#'   names as context for the model.
#' @param engine A [laya_engine()]. Defaults to [laya_default_engine()].
#' @param ... Passed to [laya_predict_batch()]: `min_confidence`, `lang`,
#'   `batch_size`, `chunk_size`, `progress` and the token budgets.
#' @param prefix A prefix for the new column names, for example `"laya_"`.
#' @param confidence Add a `<id>_confidence` column per question?
#' @param probabilities Add a `<id>_probabilities` list-column per question,
#'   holding each option's probability as a named numeric vector?
#' @return `data` with the new columns. Rows whose state columns are all
#'   missing get `NA` answers instead of a prediction.
#' @seealso [laya_predict_batch()] for the full results.
#' @examples
#' if (laya_model_available()) {
#'   tickets <- data.frame(
#'     subject = c("Duplicate charge", "App crashes on login"),
#'     body = c("We were billed twice. Refund it or we cancel.", "Since the update I can't log in.")
#'   )
#'   qs <- laya_questions(
#'     department = laya_choice("Which department should handle this?",
#'                              billing = "invoices, refunds", technical = "bugs, outages"),
#'     churn_risk = laya_noul("Does the customer threaten to cancel?")
#'   )
#'   laya_annotate(tickets, qs, state = c("subject", "body"))
#' }
#' @export
laya_annotate <- function(data, questions, state, engine = laya_default_engine(), ...,
                          prefix = "", confidence = TRUE, probabilities = FALSE) {
  if (!is.data.frame(data)) {
    laya_abort("{.arg data} must be a data frame.", kind = "invalid_argument")
  }
  questions <- as_laya_questions(questions)
  state_hint <- c(i = "For example {.code state = \"text\"} or {.code state = c(\"subject\", \"body\")}.")
  if (missing(state)) {
    laya_abort(c("{.arg state} must name the column(s) the model reads.", state_hint),
               kind = "invalid_argument")
  }
  state_expr <- substitute(state)
  state <- tryCatch(state, error = function(e) e)
  if (inherits(state, "error") || !is.character(state) || !length(state) || anyNA(state)) {
    # Bare column names, as in dplyr: `state = c(subject, body)` either fails to
    # evaluate or finds an unrelated object (`body` is a base function).
    bare <- bare_names(state_expr)
    if (length(bare) && (inherits(state, "error") || any(bare %in% names(data)))) {
      suggestion <- paste(deparse(bare), collapse = "")
      laya_abort(c("{.arg state} takes column names as strings, not bare names.",
                   i = "Use {.code state = {suggestion}}."),
                 kind = "invalid_argument")
    }
    if (inherits(state, "error")) stop(state)
    laya_abort(c("{.arg state} must name the column(s) the model reads.", state_hint),
               kind = "invalid_argument")
  }
  unknown <- setdiff(state, names(data))
  if (length(unknown)) {
    laya_abort("Column{?s} {.val {unknown}} not found in {.arg data}.", kind = "invalid_argument")
  }
  if (!is.character(prefix) || length(prefix) != 1 || is.na(prefix)) {
    laya_abort("{.arg prefix} must be a single string.", kind = "invalid_argument")
  }

  ids <- names(questions)
  new_cols <- paste0(prefix, ids)
  clash <- intersect(c(new_cols, paste0(new_cols, "_confidence"), paste0(new_cols, "_abstained"),
                       paste0(new_cols, "_probabilities")), names(data))
  if (length(clash)) {
    laya_abort(c("{.arg data} already has column{?s} {.val {clash}}.",
                 i = "Use {.arg prefix} to name the new columns differently."),
               kind = "invalid_argument")
  }

  n <- nrow(data)
  states <- lapply(seq_len(n), function(i) {
    if (length(state) == 1) {
      v <- data[[state]][[i]]
      if (is.factor(v)) v <- as.character(v)
      if (length(v) == 1 && is.na(v)) NULL else v
    } else {
      row <- row_as_list(data[state], i)
      if (all(vapply(row, function(v) length(v) == 1 && is.na(v), logical(1)))) NULL else row
    }
  })
  todo <- which(!vapply(states, is.null, logical(1)))
  results <- vector("list", n)
  if (length(todo)) {
    results[todo] <- unclass(laya_predict_batch(states[todo], questions, engine = engine, ...))
  }

  for (k in seq_along(ids)) {
    id <- ids[[k]]
    q <- questions[[id]]
    answers <- lapply(results, function(r) if (is.null(r)) NULL else r$answers[[id]])
    data[[new_cols[[k]]]] <- answer_column(q, answers)
    if (isTRUE(confidence)) {
      data[[paste0(new_cols[[k]], "_confidence")]] <-
        vapply(answers, function(a) as.numeric(a$confidence %||% NA_real_), numeric(1))
    }
    if (any(vapply(answers, function(a) !is.null(a$abstention), logical(1)))) {
      data[[paste0(new_cols[[k]], "_abstained")]] <-
        vapply(answers, function(a) if (is.null(a$abstention)) NA else a$abstention == "abstained",
               logical(1))
    }
    if (isTRUE(probabilities)) {
      data[[paste0(new_cols[[k]], "_probabilities")]] <- lapply(answers, answer_probabilities)
    }
  }
  data
}

# The names in `x` or `c(x, y)`, or character(0) for any other expression.
bare_names <- function(expr) {
  if (is.symbol(expr)) return(as.character(expr))
  if (is.call(expr) && identical(expr[[1]], quote(c)) && length(expr) > 1) {
    args <- as.list(expr)[-1]
    if (is.null(names(args)) && all(vapply(args, is.symbol, logical(1)))) {
      return(vapply(args, as.character, character(1)))
    }
  }
  character(0)
}

answer_column <- function(q, answers) {
  switch(
    q$type,
    choice = {
      labels <- choice_labels(q, answers)
      chosen <- vapply(answers, function(a) a$choice %||% NA_character_, character(1))
      factor(chosen, levels = labels)
    },
    score = vapply(answers, function(a) as.numeric(a$score %||% NA_real_), numeric(1)),
    noul = vapply(answers, function(a) as.numeric(a$noul %||% NA_real_), numeric(1)),
    vapply(answers, function(a) NA_real_, numeric(1))
  )
}

# The option labels as the engine reports them; from the question when no
# row was predicted.
choice_labels <- function(q, answers) {
  for (a in answers) if (!is.null(a)) return(names(a$probabilities))
  crit <- q$criteria
  if (!is.null(names(crit))) names(crit) else vapply(crit, as.character, character(1))
}

answer_probabilities <- function(a) {
  if (is.null(a)) return(NULL)
  switch(
    a$type,
    choice = unlist(a$probabilities),
    score = {
      lv <- vapply(a$legend, function(l) if (is.character(l)) l else as.character(to_json(l)),
                   character(1))
      stats::setNames(as.numeric(unlist(a$probabilities)), lv)
    },
    noul = c(false = 1 - a$noul, true = a$noul),
    NULL
  )
}
