# Prediction (plan 7.4).

#' Answer typed questions about a state
#'
#' `laya_predict()` answers every question about one state in a single
#' forward pass. `laya_predict_batch()` does the same for many states.
#' `laya_predict_long()` scans a state longer than the model's context in
#' overlapping windows and keeps, per question, the most confident window.
#'
#' A state is either a single string, used verbatim, or a named list, which
#' the model reads as a JSON object (field order is kept). A one-row data
#' frame is read as a named list.
#'
#' @param state A string, a named list, or a one-row data frame.
#' @param questions A question set from [laya_questions()] or
#'   [laya_preset()], or anything [as_laya_questions()] accepts.
#' @param engine A [laya_engine()]. Defaults to [laya_default_engine()].
#' @param ... Must be empty; the options below are named.
#' @param min_confidence Optional abstention gate: a threshold in `[0, 1]`,
#'   or a named numeric vector of thresholds per option-count bucket (names
#'   from [laya_bucket_keys()], plus `"default"`). The threshold is compared
#'   with each answer's `answer_confidence` (for a choice question, the
#'   chosen option's probability), as in the Python SDK. Every answer then
#'   reports `abstention`: `"passed"`, `"abstained"` or `"unevaluated"`.
#' @param lang Optional language code (e.g. `"fr"`) selecting per-language
#'   calibration temperatures, when the engine has them.
#' @param max_len,head_max_len Optional per-call token budgets overriding the
#'   checkpoint's: the whole sequence, and the part spent on a question's
#'   options.
#' @return `laya_predict()` and `laya_predict_long()` return a `laya_result`;
#'   `laya_predict_batch()` returns a `laya_batch_result` (a list of
#'   `laya_result`s, in input order). See [laya_result] for how to read them.
#' @examples
#' if (laya_model_available()) {
#'   qs <- laya_questions(
#'     department = laya_choice("Which department should handle this?",
#'                              billing = "invoices, refunds",
#'                              technical = "bugs, outages"),
#'     churn_risk = laya_noul("Does the user threaten to cancel?")
#'   )
#'   res <- laya_predict("I was billed twice. Refund me or I cancel.", qs)
#'   res
#'   as.data.frame(res)
#'
#'   laya_predict_batch(c("Refund please", "The app crashes"), qs)
#' }
#' @export
laya_predict <- function(state, questions, engine = laya_default_engine(), ...,
                         min_confidence = NULL, lang = NULL,
                         max_len = NULL, head_max_len = NULL) {
  check_dots_empty(...)
  state <- prepare_state(state)
  questions <- as_laya_questions(questions)
  opts <- predict_options(min_confidence, lang, max_len, head_max_len)
  ptr <- engine_ptr(engine)
  json <- rs_unwrap(rs_predict(ptr, as.character(to_json(state)), questions_json(questions), opts))
  new_laya_result(from_json(json))
}

#' @rdname laya_predict
#' @param states A character vector, a list of states, or a data frame
#'   (each row becomes a named list).
#' @param batch_size States per forward pass. Defaults to the
#'   `layaR.batch_size` option, or 1: on a CPU, one state per pass is usually
#'   fastest, because a batch pads every state to the longest one (see
#'   `vignette("models-and-performance", package = "layaR")`). Larger batches
#'   can pay off on other hardware. `NULL` sends each chunk in one pass, as
#'   the Python SDK does by default. Results are the same either way.
#' @param sort_by_length Group similarly sized states within a chunk to
#'   reduce padding (only with a `batch_size` above 1 and smaller than the
#'   chunk).
#' @param chunk_size States sent to the engine per call. Between chunks R can
#'   be interrupted and the progress bar updates.
#' @param progress Show a progress bar? Defaults to `TRUE` in interactive
#'   sessions with more than one chunk.
#' @export
laya_predict_batch <- function(states, questions, engine = laya_default_engine(), ...,
                               batch_size = getOption("layaR.batch_size", 1L),
                               sort_by_length = FALSE,
                               min_confidence = NULL, lang = NULL,
                               max_len = NULL, head_max_len = NULL,
                               chunk_size = 64L, progress = interactive()) {
  check_dots_empty(...)
  states <- prepare_states(states)
  questions <- as_laya_questions(questions)
  chunk_size <- int_or_null(chunk_size, "chunk_size")
  if (is.null(chunk_size) || chunk_size < 1) {
    laya_abort("{.arg chunk_size} must be at least 1.", kind = "invalid_argument")
  }
  opts <- as.character(to_json(compact(list(
    batch_size = int_or_null(batch_size, "batch_size"),
    sort_by_length = if (isTRUE(sort_by_length)) TRUE else NULL,
    min_confidence = min_confidence_json(min_confidence),
    lang = lang_arg(lang),
    max_len = int_budget(max_len, "max_len"),
    head_max_len = int_budget(head_max_len, "head_max_len")
  )), empty_object = TRUE))
  ptr <- engine_ptr(engine)
  qjson <- questions_json(questions)

  n <- length(states)
  starts <- if (n) seq(1L, n, by = chunk_size) else integer()
  out <- vector("list", n)
  show <- isTRUE(progress) && length(starts) > 1
  if (show) {
    bar <- cli::cli_progress_bar("Predicting", total = n, clear = TRUE, .envir = environment())
  }
  for (start in starts) {
    idx <- start:min(n, start + chunk_size - 1L)
    chunk_json <- as.character(to_json(unname(states[idx]), array = TRUE))
    json <- rs_unwrap(rs_predict_batch(ptr, chunk_json, qjson, opts))
    out[idx] <- lapply(from_json(json), new_laya_result)
    if (show) cli::cli_progress_update(id = bar, inc = length(idx), .envir = environment())
  }
  structure(out, class = "laya_batch_result")
}

#' @rdname laya_predict
#' @param window,stride Optional scan window and stride, in tokens. By
#'   default the window is the room the questions leave in one sequence and
#'   the stride is half the window.
#' @export
laya_predict_long <- function(state, questions, engine = laya_default_engine(), ...,
                              window = NULL, stride = NULL, batch_size = NULL, lang = NULL) {
  check_dots_empty(...)
  state <- prepare_state(state)
  questions <- as_laya_questions(questions)
  opts <- as.character(to_json(compact(list(
    window = int_or_null(window, "window"),
    stride = int_or_null(stride, "stride"),
    batch_size = int_or_null(batch_size, "batch_size"),
    lang = lang_arg(lang)
  )), empty_object = TRUE))
  ptr <- engine_ptr(engine)
  json <- rs_unwrap(rs_predict_long(ptr, as.character(to_json(state)), questions_json(questions), opts))
  new_laya_result(from_json(json))
}

#' @rdname laya_predict
#' @param object A `laya_engine`, for the [stats::predict()] method.
#' @exportS3Method stats::predict
predict.laya_engine <- function(object, state, questions, ...) {
  laya_predict(state, questions, engine = object, ...)
}

#' Bucket names for `min_confidence`
#'
#' A per-bucket `min_confidence` gives a threshold per question type and
#' option count. These are the valid names; `"default"` also applies to every
#' bucket not named.
#' @return A character vector.
#' @examples
#' laya_bucket_keys()
#' @export
laya_bucket_keys <- function() {
  rs_bucket_keys()
}

# ---- argument preparation ----

prepare_state <- function(state, call = parent.frame()) {
  if (is.null(state)) {
    laya_abort("{.arg state} can't be {.code NULL}.", kind = "invalid_state", call = call)
  }
  if (is.data.frame(state)) {
    if (nrow(state) != 1) {
      laya_abort("A data-frame {.arg state} must have exactly one row; use {.fn laya_predict_batch} for more.",
                 kind = "invalid_argument", call = call)
    }
    return(row_as_list(state, 1L))
  }
  if (is.factor(state)) state <- as.character(state)
  if (is.atomic(state) && is.null(names(state))) {
    if (length(state) != 1) {
      laya_abort(c("{.arg state} must be a single string or a named list.",
                   i = "For several states use {.fn laya_predict_batch}."),
                 kind = "invalid_argument", call = call)
    }
    if (is.na(state)) {
      laya_abort("{.arg state} can't be {.code NA}.", kind = "invalid_state", call = call)
    }
    return(if (is.character(state)) enc2utf8(state) else state)
  }
  state
}

prepare_states <- function(states, call = parent.frame()) {
  if (is.data.frame(states)) {
    return(lapply(seq_len(nrow(states)), function(i) row_as_list(states, i)))
  }
  if (is.factor(states)) states <- as.character(states)
  if (is.character(states)) {
    if (anyNA(states)) {
      laya_abort("{.arg states} contains {.code NA} at position{?s} {which(is.na(states))}.",
                 kind = "invalid_state", call = call)
    }
    return(as.list(enc2utf8(states)))
  }
  if (!is.list(states)) {
    laya_abort("{.arg states} must be a character vector, a list of states or a data frame.",
               kind = "invalid_argument", call = call)
  }
  nulls <- which(vapply(states, is.null, logical(1)))
  if (length(nulls)) {
    laya_abort("{.arg states} contains {.code NULL} at position{?s} {nulls}.",
               kind = "invalid_state", call = call)
  }
  lapply(states, function(s) if (is.factor(s)) as.character(s) else s)
}

row_as_list <- function(df, i) {
  row <- lapply(df, function(col) {
    v <- col[[i]]
    if (is.factor(v)) as.character(v) else v
  })
  names(row) <- names(df)
  row
}

predict_options <- function(min_confidence, lang, max_len, head_max_len, call = parent.frame()) {
  as.character(to_json(compact(list(
    min_confidence = min_confidence_json(min_confidence, call = call),
    lang = lang_arg(lang, call = call),
    max_len = int_budget(max_len, "max_len", call = call),
    head_max_len = int_budget(head_max_len, "head_max_len", call = call)
  )), empty_object = TRUE))
}

min_confidence_json <- function(x, call = parent.frame()) {
  if (is.null(x)) return(NULL)
  if (!is.numeric(x) || !length(x) || anyNA(x)) {
    laya_abort("{.arg min_confidence} must be a number in [0, 1] or a named numeric vector.",
               kind = "invalid_argument", call = call)
  }
  if (is.null(names(x))) {
    if (length(x) != 1) {
      laya_abort("An unnamed {.arg min_confidence} must be a single number; name per-bucket thresholds (see {.fn laya_bucket_keys}).",
                 kind = "invalid_argument", call = call)
    }
    return(unname(as.numeric(x)))
  }
  as.list(x)
}

lang_arg <- function(x, call = parent.frame()) {
  if (is.null(x)) return(NULL)
  if (!is.character(x) || length(x) != 1 || is.na(x)) {
    laya_abort("{.arg lang} must be a single string such as {.val fr}.",
               kind = "invalid_argument", call = call)
  }
  x
}

int_budget <- function(x, arg, call = parent.frame()) {
  if (is.null(x)) return(NULL)
  if (!is.numeric(x) || length(x) != 1 || is.na(x) || x != round(x)) {
    laya_abort("{.arg {arg}} must be a single whole number.", kind = "invalid_argument", call = call)
  }
  as.integer(x)
}
