# Dev script: run laya-rust's golden cases through the R bridge and compare
# with Python's recorded results. Usage (from the package root):
#   Rscript data-raw/parity_sweep.R [checkpoint]
# Becomes tests/testthat/test-parity.R in Phase 4.
devtools::load_all(quiet = TRUE)
args <- commandArgs(trailingOnly = TRUE)
checkpoint <- if (length(args)) args[[1]] else "multilingual"
dir <- file.path(tools::R_user_dir("layaR", "cache"), "onnx", checkpoint)
files <- Sys.glob(file.path("laya-repo/laya-rust/tests/golden", checkpoint, "case_*.json"))
table_key <- vapply(files, function(f) {
  lt <- jsonlite::fromJSON(f, simplifyVector = FALSE)$lang_temperatures
  if (is.null(lt)) "" else as.character(jsonlite::toJSON(lt, auto_unbox = TRUE, digits = NA))
}, character(1))
files <- files[order(table_key != "", table_key)]
# Keep one engine at a time (each holds ~1 GB): cases are sorted by their
# lang_temperatures table so the engine is rebuilt only when the table changes.
current <- list(key = NULL, engine = NULL)
engine_for <- function(lt) {
  key <- if (is.null(lt)) "" else as.character(to_json(lt))
  if (!identical(key, current$key)) {
    if (!is.null(current$engine)) rs_engine_close(current$engine)
    current <<- list(key = key, engine = NULL)
    opts <- if (is.null(lt)) "{}" else as.character(to_json(list(lang_temperatures = lt)))
    res <- rs_engine_new(dir, opts)
    if (!res$ok) return(res)
    current$engine <<- res$value
    gc()
  }
  current$engine
}
diffs <- character()
cmp <- function(want, got, path) {
  # Python's batch path names the model "laya-rl-agent-onnx"; laya-onnx reports
  # "laya-rl-agent" everywhere (upstream's own parity tests don't compare it for
  # batches either).
  if (grepl("\\$model$", path)) return(invisible())
  if (is.list(want) && !is.null(names(want))) {
    if (!identical(names(want), names(got)))
      diffs <<- c(diffs, sprintf("%s: keys want [%s] got [%s]", path,
        paste(names(want), collapse = ","), paste(names(got), collapse = ",")))
    for (k in intersect(names(want), names(got))) cmp(want[[k]], got[[k]], paste0(path, "$", k))
  } else if (is.list(want)) {
    if (length(want) != length(got)) diffs <<- c(diffs, sprintf("%s: length %d vs %d", path, length(want), length(got)))
    else for (i in seq_along(want)) cmp(want[[i]], got[[i]], sprintf("%s[[%d]]", path, i))
  } else if (is.numeric(want) && is.numeric(got)) {
    tol <- if (grepl("\\$score$", path)) 2e-3 else 2e-4
    if (abs(want - got) > tol) diffs <<- c(diffs, sprintf("%s: %g vs %g", path, want, got))
  } else if (!identical(want, got)) {
    diffs <<- c(diffs, sprintf("%s: %s vs %s", path, format(want), format(got)))
  }
}
tally <- c(ok = 0, mismatch = 0, error_ok = 0, error_mismatch = 0, skipped = 0)
t0 <- Sys.time()
for (f in files) {
  d <- jsonlite::fromJSON(f, simplifyVector = FALSE)
  name <- basename(f)
  if (is.null(d$questions) || !is.null(d$shortlist_k) || !is.null(d$reduced_questions)) {
    tally["skipped"] <- tally["skipped"] + 1; next
  }
  eng <- engine_for(d$lang_temperatures)
  opts <- if (is.null(d$options)) "{}" else as.character(to_json(d$options))
  q <- as.character(to_json(d$questions))
  if (is.list(eng) && isFALSE(eng$ok)) {
    res <- eng; want <- d$result
  } else if (!is.null(d$windows)) {
    res <- rs_predict_long(eng, as.character(to_json(d$state)), q, opts); want <- d$result
  } else if (!is.null(d$states) || !is.null(d$results)) {
    states <- as.character(to_json(d$states, array = TRUE))
    res <- rs_predict_batch(eng, states, q, opts); want <- d$results
  } else {
    res <- rs_predict(eng, as.character(to_json(d$state)), q, opts); want <- d$result
  }
  if (!is.null(d$error_type)) {
    if (isFALSE(res$ok)) tally["error_ok"] <- tally["error_ok"] + 1
    else {
      tally["error_mismatch"] <- tally["error_mismatch"] + 1
      diffs <- c(diffs, sprintf("%s: expected %s, got success", name, d$error_type))
    }
    next
  }
  if (!isTRUE(res$ok)) {
    tally["mismatch"] <- tally["mismatch"] + 1
    diffs <- c(diffs, sprintf("%s: %s: %s", name, res$error_kind, substr(res$error_message, 1, 200)))
    next
  }
  before <- length(diffs)
  cmp(want, from_json(res$value), name)
  k <- if (length(diffs) == before) "ok" else "mismatch"
  tally[k] <- tally[k] + 1
}
cat(sprintf("%s: %d cases in %.0f s\n", checkpoint, length(files), as.numeric(Sys.time() - t0, units = "secs")))
print(tally)
cat(unique(diffs), sep = "\n")
