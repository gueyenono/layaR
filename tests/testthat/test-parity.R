# Parity with the Python SDK, on cases recorded by laya-rust's golden suite
# (see data-raw/make_fixtures.R). Each case runs through the bridge with its
# Python-format options; plain single-state cases also run through
# laya_predict(). Needs the exported models, so it skips without them.
#
# By default only the core cases run (about 50 per checkpoint, ~2 minutes);
# set LAYAR_PARITY=all to run all 117 (~6 minutes per checkpoint).

parity_diffs <- function(want, got, path = "") {
  # Python's batch and long paths name the model "laya-rl-agent-onnx"; laya-onnx
  # says "laya-rl-agent" everywhere, and upstream's own parity tests skip it.
  if (grepl("\\$model$", path)) return(character())
  if (is.list(want) && !is.null(names(want))) {
    out <- character()
    if (!identical(names(want), names(got))) {
      out <- sprintf("%s: keys [%s] vs [%s]", path, toString(names(want)), toString(names(got)))
    }
    for (k in intersect(names(want), names(got))) {
      out <- c(out, parity_diffs(want[[k]], got[[k]], paste0(path, "$", k)))
    }
    return(out)
  }
  if (is.list(want)) {
    if (!is.list(got) || length(want) != length(got)) {
      return(sprintf("%s: length %d vs %d", path, length(want), length(got)))
    }
    return(unlist(lapply(seq_along(want), function(i) {
      parity_diffs(want[[i]], got[[i]], sprintf("%s[[%d]]", path, i))
    })))
  }
  if (is.numeric(want) && is.numeric(got) && length(want) == 1 && length(got) == 1) {
    # Python rounds to 4 decimals; a score sums level * p over several levels.
    tol <- if (grepl("\\$score$", path)) 2e-3 else 2e-4
    if (abs(want - got) > tol) return(sprintf("%s: %s vs %s", path, want, got))
    return(character())
  }
  if (!identical(want, got)) {
    return(sprintf("%s: %s vs %s", path, format(want), format(got)))
  }
  character()
}

strip_classes <- function(x) {
  if (is.list(x)) {
    nms <- names(x)
    x <- lapply(unclass(x), strip_classes)
    names(x) <- nms
  }
  x
}

run_parity_case <- function(case, engine) {
  ptr <- engine_ptr(engine)
  opts <- if (is.null(case$options)) "{}" else as.character(to_json(case$options))
  questions <- as.character(to_json(case$questions, empty_object = TRUE))
  res <- switch(
    case$kind,
    predict = rs_predict(ptr, as.character(to_json(case$state)), questions, opts),
    batch = rs_predict_batch(ptr, as.character(to_json(case$states, array = TRUE)), questions, opts),
    long = rs_predict_long(ptr, as.character(to_json(case$state)), questions, opts)
  )
  # rs_unwrap() raises the same classed condition users see.
  from_json(suppressWarnings(rs_unwrap(res)))
}

check_parity <- function(checkpoint) {
  skip_on_cran()
  skip_if_not(laya_model_available(checkpoint), paste("no local", checkpoint, "model"))
  skip_without_runtime()
  fixture <- jsonlite::fromJSON(test_path("fixtures", "parity", paste0(checkpoint, ".json")),
                                simplifyVector = FALSE)
  cases <- fixture$cases
  if (!identical(Sys.getenv("LAYAR_PARITY"), "all")) {
    cases <- Filter(function(case) isTRUE(case$core), cases)
  }
  # One engine at a time (each holds about 1 GB), rebuilt only when the
  # lang_temperatures table changes.
  key <- vapply(cases, function(case) {
    if (is.null(case$lang_temperatures)) "" else as.character(to_json(case$lang_temperatures))
  }, character(1))
  cases <- cases[order(key != "", key)]
  key <- sort(key)
  engine <- NULL
  on.exit(if (!is.null(engine)) laya_engine_close(engine), add = TRUE)

  for (i in seq_along(cases)) {
    case <- cases[[i]]
    if (i == 1 || key[[i]] != key[[i - 1]]) {
      if (!is.null(engine)) laya_engine_close(engine)
      engine <- NULL
      gc()
      # Loading warns about temperatures the engine clamps (the english
      # checkpoint ships some, and some fixtures do on purpose).
      engine <- withCallingHandlers(
        laya_engine(checkpoint, intra_op_threads = 2, lang_temperatures = case$lang_temperatures),
        laya_warning = function(w) invokeRestart("muffleWarning")
      )
    }
    label <- paste0(checkpoint, "/", case$name)
    if (!is.null(case$error)) {
      expect_error(run_parity_case(case, engine), class = paste0("laya_error_", case$error$kind),
                   label = label)
      next
    }
    got <- run_parity_case(case, engine)
    diffs <- parity_diffs(case$expected, got, label)
    expect(length(diffs) == 0,
           paste(c(paste(label, "differs from Python:"), head(diffs, 10)), collapse = "\n"))

    # The public API gives the same answers for a plain single state.
    if (case$kind == "predict" && is.null(case$options) && is.null(case$lang_temperatures) &&
        length(case$questions)) {
      res <- laya_predict(case$state, as_laya_questions(case$questions), engine = engine)
      diffs <- parity_diffs(case$expected, strip_classes(res), paste0(label, " (laya_predict)"))
      expect(length(diffs) == 0, paste(head(diffs, 10), collapse = "\n"))
    }
  }
}

test_that("multilingual results match the Python SDK", {
  check_parity("multilingual")
})

test_that("english results match the Python SDK", {
  check_parity("english")
})

test_that("typed-decisions results match the Python SDK", {
  check_parity("typed-decisions")
})
