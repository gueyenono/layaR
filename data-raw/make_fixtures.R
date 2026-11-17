# Build the parity fixtures used by tests/testthat/test-parity.R.
#
# Reads laya-rust's golden cases (recorded from the Python SDK) and keeps only
# what an R-level test needs: the inputs (state or states, questions, options,
# lang_temperatures) and Python's result or error. Token ids, logits and
# per-question renderings are dropped. Usage, from the package root:
#
#   Rscript data-raw/make_fixtures.R [path/to/laya-rust/tests/golden]
#
# Writes tests/testthat/fixtures/parity/<checkpoint>.json.

args <- commandArgs(trailingOnly = TRUE)
golden <- if (length(args)) args[[1]] else "laya-repo/laya-rust/tests/golden"
out_dir <- "tests/testthat/fixtures/parity"
checkpoints <- c("english", "multilingual")

# Run by default (about 30 cases per checkpoint). Every error case also runs by
# default, since errors fail before the forward pass. Set LAYAR_PARITY=all to
# run everything.
core <- c(
  "quickstart", "arabic", "cjk", "sample_app_english", "sample_app_hindi",
  "dict_state", "list_state", "json_escaping", "criterion_shapes",
  "choice_criteria_list", "nonstring_instructions", "single_option",
  "many_options", "mask_injection", "min_confidence_scalar", "min_confidence_map",
  "budget_max_len", "budget_head_squeezed", "lang_replace_de",
  "lang_with_min_confidence", "batch_mixed", "batch_chunked", "batch_sort_on",
  "batch_truncated", "batch_size_negative", "batch_empty_states",
  "batch_lang_budgets", "long_short", "long_dict", "long_multi_chunk"
)

# Python raises ValueError/TypeError; the R condition class is more specific.
error_kind <- function(message) {
  rules <- c(
    "option markers fit" = "no_markers",
    "min_confidence" = "invalid_min_confidence",
    "state must not be None" = "invalid_state",
    "only aggregate=" = "unsupported_aggregate",
    "stride=" = "invalid_window",
    "options fill the whole sequence" = "invalid_window"
  )
  hit <- names(rules)[vapply(names(rules), grepl, logical(1), x = message, fixed = TRUE)]
  if (!length(hit)) stop("No error kind rule for: ", message)
  unname(rules[[hit[[1]]]])
}

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
for (ck in checkpoints) {
  files <- sort(Sys.glob(file.path(golden, ck, "case_*.json")))
  cases <- list()
  for (f in files) {
    d <- jsonlite::fromJSON(f, simplifyVector = FALSE)
    # Shortlist cases test an upstream helper that layaR doesn't wrap.
    if (!is.null(d$shortlist_k) || !is.null(d$reduced_questions)) next
    # Long-scan error cases record no windows; only their name says so.
    is_long <- !is.null(d$windows) || (!is.null(d$error_type) && startsWith(d$name, "long_"))
    kind <- if (is_long) "long" else if (!is.null(d$states)) "batch" else "predict"
    case <- list(name = d$name, kind = kind, core = d$name %in% core || !is.null(d$error_type))
    if (kind == "batch") case$states <- d$states else case$state <- d$state
    case$questions <- d$questions
    case$options <- if (length(d$options)) d$options else NULL
    case$lang_temperatures <- d$lang_temperatures
    if (!is.null(d$error_type)) {
      case$error <- list(type = d$error_type, message = d$error_message,
                         kind = error_kind(d$error_message))
    } else {
      case$expected <- if (kind == "batch") d$results else d$result
    }
    cases[[length(cases) + 1]] <- case
  }
  missing <- setdiff(core, vapply(cases, `[[`, "", "name"))
  if (length(missing)) stop("Core cases not found for ", ck, ": ", paste(missing, collapse = ", "))
  # Doubles keep 17 significant digits and a decimal point, so states reach
  # the engine exactly as Python recorded them (see R/json.R).
  json <- jsonlite::toJSON(
    list(checkpoint = ck, source = "laya-rust/tests/golden", cases = cases),
    auto_unbox = TRUE, digits = I(17), always_decimal = TRUE, null = "null", na = "null"
  )
  path <- file.path(out_dir, paste0(ck, ".json"))
  writeLines(json, path, useBytes = TRUE)
  message(sprintf("%s: %d cases (%d core), %.0f KB", ck, length(cases),
                  sum(vapply(cases, `[[`, NA, "core")), file.size(path) / 1024))
}
