# Text utilities that need no model (plan 7.8): language detection and email
# cleaning. Both are ports of the Python SDK's helpers, checked against
# Python-recorded probes.

#' Detect the language of states
#'
#' Reads each state's text (string values only; keys are ignored) and reports
#' its dominant script, a best-effort language guess for Latin-script text,
#' and whether the English checkpoint can read it. Use it to pick a
#' checkpoint: `"english"` when `is_english` is `TRUE`, `"multilingual"`
#' otherwise. No model is needed.
#'
#' A structured state that reads English as a whole is also checked field by
#' field and line by line, so a short message in another language next to a
#' long English stack trace still counts as non-English (`mixed_segment`
#' shows the part that decided it).
#'
#' @param states A character vector of texts, a single state (a named list),
#'   a list of states, or a data frame (one state per row).
#' @return A data frame with one row per state and columns `script`,
#'   `language` (an ISO 639-1 code, or `NA` when undecided or not Latin),
#'   `is_english`, `language_undecided`, `diacritic_rate`,
#'   `non_latin_fraction`, `mixed_segment` and `script_profile` (a list-column
#'   of named numeric vectors: the share of letters in each script).
#' @examples
#' laya_detect_language(c(
#'   "Please refund the duplicate charge",
#'   "मार्च का बिल दो बार लिया गया",
#'   "glömt lösenord"
#' ))
#' laya_detect_language(list(subject = "Refund", body = "Hola, me cobraron dos veces. \u00bfPueden devolverme el dinero?"))
#' @export
laya_detect_language <- function(states) {
  if (is.list(states) && !is.data.frame(states) && !is.null(names(states))) {
    states <- list(states)
  }
  states <- prepare_states(states)
  json <- rs_unwrap(rs_detect_language(as.character(to_json(unname(states), array = TRUE))))
  rows <- from_json(json)
  chr <- function(field) vapply(rows, function(r) r[[field]] %||% NA_character_, character(1))
  lgl <- function(field) vapply(rows, function(r) isTRUE(r[[field]]), logical(1))
  num <- function(field) vapply(rows, function(r) as.numeric(r[[field]]), numeric(1))
  out <- data.frame(
    script = chr("script"),
    language = chr("language"),
    is_english = lgl("is_english"),
    language_undecided = lgl("language_undecided"),
    diacritic_rate = num("diacritic_rate"),
    non_latin_fraction = num("non_latin_fraction"),
    mixed_segment = chr("mixed_segment"),
    stringsAsFactors = FALSE
  )
  out$script_profile <- lapply(rows, function(r) unlist(r$script_profile) %||% numeric())
  out
}

#' Clean email bodies
#'
#' Removes quoted replies, reply headers, signatures and legal disclaimers so
#' the model reads only the sender's message. A port of the Python SDK's
#' `clean_email_body()`, with the same results.
#'
#' @param body A character vector of email bodies. `NA` stays `NA`.
#' @param max_chars The most characters to keep, applied after cleaning.
#'   Cleaning only looks at the first `4 * max_chars` characters, so raise it
#'   for long messages. As in Python, `0` returns `""` and a negative value
#'   trims from the end; it never means "no limit".
#' @return A character vector the same length as `body`.
#' @seealso [laya_email_state()]
#' @examples
#' laya_clean_email(paste(
#'   "Please refund the duplicate charge.",
#'   "",
#'   "Best,",
#'   "Ana",
#'   "",
#'   "On Mon, 3 Mar 2025 at 10:00, Support <help@example.com> wrote:",
#'   "> How can we help?",
#'   sep = "\n"
#' ))
#' @export
laya_clean_email <- function(body, max_chars = 3000) {
  if (is.factor(body)) body <- as.character(body)
  if (!is.character(body)) {
    laya_abort("{.arg body} must be a character vector.", kind = "invalid_argument")
  }
  max_chars <- check_max_chars(max_chars)
  if (!length(body)) return(character())
  json <- rs_unwrap(rs_clean_email(as.character(to_json(as.list(unname(enc2utf8(body))), array = TRUE)),
                                   max_chars))
  out <- vapply(from_json(json), function(x) x %||% NA_character_, character(1))
  names(out) <- names(body)
  out
}

#' Build an email state
#'
#' Builds the state the Python SDK's `email_state()` builds: `subject`, a
#' cleaned `body`, `from` when a `sender` is given, then any extra fields. Pass
#' the result to [laya_predict()], or use it with the `"email"` preset
#' ([laya_preset()]).
#'
#' @param subject,body The email's subject and body, single strings.
#' @param sender Optional sender address, stored in the state's `from` field.
#' @param ... Extra named fields to add to the state (for example
#'   `ticket_id = 4411`). `NULL` fields are dropped, as in Python.
#' @param clean Clean the body with [laya_clean_email()]? If `FALSE` the body
#'   is passed through whole.
#' @param max_chars Passed to [laya_clean_email()] when `clean = TRUE`.
#' @return A named list, ready to use as a state.
#' @examples
#' laya_email_state(
#'   subject = "Duplicate charge",
#'   body = "We were billed twice.\n\n-- \nAna Muller\nAcme Corp",
#'   sender = "ana@example.com",
#'   ticket_id = 4411L
#' )
#' @export
laya_email_state <- function(subject, body, sender = NULL, ..., clean = TRUE, max_chars = 3000) {
  single_string <- function(x, arg) {
    if (!is.character(x) || length(x) != 1 || is.na(x)) {
      laya_abort("{.arg {arg}} must be a single string.", kind = "invalid_argument")
    }
    enc2utf8(x)
  }
  subject <- single_string(subject, "subject")
  body <- single_string(body, "body")
  sender <- if (is.null(sender)) "" else single_string(sender, "sender")
  extra <- list(...)
  if (length(extra) && (is.null(names(extra)) || any(names(extra) == ""))) {
    laya_abort("Extra fields in {.arg ...} must be named.", kind = "invalid_argument")
  }
  extra <- compact(extra)
  if (!is.logical(clean) || length(clean) != 1 || is.na(clean)) {
    laya_abort("{.arg clean} must be {.code TRUE} or {.code FALSE}.", kind = "invalid_argument")
  }
  json <- rs_unwrap(rs_email_state(subject, body, sender, clean, check_max_chars(max_chars),
                                   as.character(to_json(extra, empty_object = TRUE))))
  from_json(json)
}

check_max_chars <- function(max_chars, call = parent.frame()) {
  if (!is.numeric(max_chars) || length(max_chars) != 1 || is.na(max_chars) ||
      max_chars != round(max_chars) || abs(max_chars) > 2^53) {
    laya_abort("{.arg max_chars} must be a single whole number.", kind = "invalid_argument",
               call = call)
  }
  as.numeric(max_chars)
}
