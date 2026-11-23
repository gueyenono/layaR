# Models and performance

``` r

library(layaR)
```

## Where models live

layaR keeps models in a per-user folder that follows CRAN’s rules
([`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html)), one
subfolder per checkpoint:

``` r

sub(path.expand("~"), "~", laya_model_root(), fixed = TRUE)
#> [1] "~/.cache/R/layaR/onnx"
```

Set the `layaR.model_root` option to keep them elsewhere, for example on
a larger disk: `options(layaR.model_root = "/data/laya-models")` in your
`.Rprofile`.

There are three ways to get a model:

- `laya_download_model("multilingual")` downloads an export from Hugging
  Face (`gueyenono/laya-onnx` by default; the `layaR.model_repo` option
  or the `repo` argument point elsewhere). The download resumes if it is
  interrupted, and nothing counts as installed until every file is
  there.
- `laya_import_model(path, "multilingual")` adds an export you made
  yourself with the Laya repository’s `export_onnx.py`. By default it
  links to the folder instead of copying 1.5 GB; `method = "copy"`
  copies it.
- A model exported for Laya’s Rust or TypeScript SDK, in their shared
  cache (`~/.cache/laya/onnx`), is found automatically. layaR reads it
  but never writes there. `options(layaR.shared_cache = FALSE)` turns
  this off.

[`laya_models()`](https://gueyenono.github.io/layaR/dev/reference/laya_models.md)
lists the three checkpoints, whether each is installed, and where it was
found;
[`laya_remove_model()`](https://gueyenono.github.io/layaR/dev/reference/laya_remove_model.md)
deletes one (an imported link is removed without touching the original
files).

Models run on ONNX Runtime, which layaR loads when the first engine is
created.
[`laya_install_runtime()`](https://gueyenono.github.io/layaR/dev/reference/laya_install_runtime.md)
downloads Microsoft’s official build once
([`laya_download_model()`](https://gueyenono.github.io/layaR/dev/reference/laya_download_model.md)
does it for you), and
[`laya_runtime_info()`](https://gueyenono.github.io/layaR/dev/reference/laya_install_runtime.md)
shows which library is used. To use a library of your own, ONNX Runtime
1.27 or newer, set the `layaR.onnxruntime` option or the
`ORT_DYLIB_PATH` environment variable to its path.

## Engines and memory

An engine is a loaded checkpoint. Loading takes a few seconds and holds
the model in memory, so create one engine and reuse it. The prediction
functions do that for you: they default to
[`laya_default_engine()`](https://gueyenono.github.io/layaR/dev/reference/laya_default_engine.md),
which loads the checkpoint named by the `layaR.checkpoint` option
(`"multilingual"` unless you set it) on first use and keeps it for the
session.

``` r

before <- rss_mb()
load_time <- system.time(engine <- laya_engine("multilingual"))[["elapsed"]]
c(load_seconds = round(load_time, 1), memory_mb = round(rss_mb() - before))
#> load_seconds    memory_mb 
#>          1.9        869.0
engine
#> <laya_engine> multilingual · fused ONNX · max_len 1024 · head_max_len 256
#>   /home/gueyenono/.cache/R/layaR/onnx/multilingual
```

Each engine holds its own copy of the model, so two engines take twice
the memory.
[`laya_engine_close()`](https://gueyenono.github.io/layaR/dev/reference/laya_engine_info.md)
frees it right away instead of waiting for garbage collection:

``` r

laya_engine_close(engine)
```

To use a different checkpoint by default, set the option before the
first prediction, for example `options(layaR.checkpoint = "english")`,
or pass `engine = laya_engine("english")` to the calls that need it.

## Threads

ONNX Runtime runs one forward pass on several cores. `intra_op_threads`
sets how many; by default ONNX Runtime picks, which usually means one
per physical core. Set the `layaR.threads` option to change the default
for every engine, for example to leave cores free for other work.

## Parallel work

**Don’t fork.** ONNX Runtime’s thread pools don’t survive `fork()`, so
an engine can’t be used inside
[`parallel::mclapply()`](https://rdrr.io/r/parallel/mclapply.html) or
`future::multicore`. layaR detects this and raises a `laya_error_forked`
error rather than letting the child process hang.

**One engine is usually enough.** A single engine already spreads each
forward pass over all cores. Running several engines in parallel on the
same machine mostly makes them compete for the same cores, while
multiplying memory use.

**Separate processes work.** In PSOCK workers
([`parallel::makePSOCKcluster()`](https://rdrr.io/r/parallel/makeCluster.html),
`future::multisession`, or `callr`), each process loads its own engine.
An engine sent to a worker, or saved with
[`saveRDS()`](https://rdrr.io/r/base/readRDS.html) and read back,
reconnects to its model folder on first use, which loads the model again
in that process. This is useful across machines, or with
`intra_op_threads` set so the workers share the cores between them.

## Speed

The rest of this vignette measures where the time goes, on the machine
below, with the multilingual checkpoint.

``` r

c(cpu = sub(".*: *", "", grep("model name", readLines("/proc/cpuinfo"), value = TRUE)[1]),
  cores = parallel::detectCores(),
  physical_cores = sub(".*: *", "", grep("cpu cores", readLines("/proc/cpuinfo"), value = TRUE)[1]))
#>                                        cpu                                      cores 
#> "Intel(R) Core(TM) i7-4790K CPU @ 4.00GHz"                                        "8" 
#>                             physical_cores 
#>                                        "4"
```

``` r

qs <- laya_questions(
  department = laya_choice("Which department should handle this request?",
                           billing = "invoices, payments, refunds",
                           technical = "bugs, outages, system errors",
                           sales = "pricing, new contracts", other = "everything else"),
  urgency = laya_score("How urgent is this request?", c("not urgent", "soon", "critical")),
  churn_risk = laya_noul("Does the customer say they will cancel or leave?")
)
set.seed(1)
openings <- c("Hi team,", "Hello,", "Urgent:", "Quick question:", "Dear support,")
issues <- c("we were billed twice for March", "the app crashes when I log in",
            "we need a quote for 50 seats", "please close my account",
            "the export to CSV fails", "our production server is down")
endings <- c("Thanks.", "Please fix this today or we will cancel.", "Any update?",
             paste(rep("We have tried everything in your documentation.", 3), collapse = " "))
texts <- paste(sample(openings, 256, TRUE), sample(issues, 256, TRUE),
               sample(endings, 256, TRUE))
summary(nchar(texts))
#>    Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
#>    38.0    47.0    71.5    87.7    87.0   190.0

engine <- laya_engine("multilingual")
invisible(laya_predict(texts[1], qs, engine = engine))   # warm up
```

### The R layer adds almost nothing

Every call crosses from R to Rust as JSON. Comparing
[`laya_predict()`](https://gueyenono.github.io/layaR/dev/reference/laya_predict.md)
with a call straight into the Rust bridge, with the JSON prepared in
advance, shows what the R side costs:

``` r

state <- texts[1]
ptr <- layaR:::engine_ptr(engine)
state_json <- as.character(layaR:::to_json(state))
qs_json <- layaR:::questions_json(qs)
opts <- layaR:::predict_options(NULL, NULL, NULL, NULL)

overhead <- bench::mark(
  laya_predict = laya_predict(state, qs, engine = engine),
  rust_only = layaR:::rs_predict(ptr, state_json, qs_json, opts),
  check = FALSE, min_iterations = 100
)
overhead[, c("expression", "min", "median")]
#> # A tibble: 2 × 3
#>   expression        min   median
#>   <bch:expr>   <bch:tm> <bch:tm>
#> 1 laya_predict    167ms    175ms
#> 2 rust_only       164ms    173ms
```

The two are within measurement noise of each other: building the JSON,
checking arguments and turning the result into a list cost almost
nothing next to the forward pass.

### Batches: padding costs more than it saves on a CPU

A forward pass can take several texts at once, but every text in it is
padded to the longest one. On a GPU batching usually wins; on this CPU
it doesn’t.
[`laya_predict_batch()`](https://gueyenono.github.io/layaR/dev/reference/laya_predict.md)
therefore sends one text per forward pass by default (`batch_size = 1`,
or the `layaR.batch_size` option):

``` r

one_by_one <- function(x) for (s in x) laya_predict(s, qs, engine = engine)
batch <- function(...) laya_predict_batch(texts[1:64], qs, engine = engine, progress = FALSE, ...)
batches <- bench::mark(
  `laya_predict() in a loop` = one_by_one(texts[1:64]),
  `batch_size = 1 (default)` = batch(),
  `batch_size = 4, sorted` = batch(batch_size = 4, sort_by_length = TRUE),
  `batch_size = 16, sorted` = batch(batch_size = 16, sort_by_length = TRUE),
  `whole chunk (NULL)` = batch(batch_size = NULL),
  check = FALSE, min_iterations = 3, filter_gc = FALSE
)
data.frame(method = as.character(batches$expression),
           seconds = round(as.numeric(batches$median), 2),
           texts_per_second = round(64 / as.numeric(batches$median), 1))
#>                     method seconds texts_per_second
#> 1 laya_predict() in a loop   10.91              5.9
#> 2 batch_size = 1 (default)   10.88              5.9
#> 3   batch_size = 4, sorted   11.74              5.4
#> 4  batch_size = 16, sorted   14.79              4.3
#> 5       whole chunk (NULL)   19.33              3.3
```

The answers are the same whatever the batch size; only the speed
changes. If you run on different hardware, try a few values of
`batch_size` with `sort_by_length = TRUE` on your own texts, and set the
`layaR.batch_size` option to the best one.

Even with the default batch size,
[`laya_predict_batch()`](https://gueyenono.github.io/layaR/dev/reference/laya_predict.md)
is the better tool for many texts than a loop: it checks the questions
once, shows a progress bar, and stops cleanly when interrupted.
`chunk_size` only decides how often R gets control back for that; it
doesn’t change throughput in any consistent way. The differences below
are run-to-run noise, and which size comes out fastest changes from one
run to the next:

``` r

chunks <- bench::mark(
  `chunk_size = 16` = laya_predict_batch(texts, qs, engine = engine, chunk_size = 16,
                                         progress = FALSE),
  `chunk_size = 64` = laya_predict_batch(texts, qs, engine = engine, chunk_size = 64,
                                         progress = FALSE),
  `chunk_size = 256` = laya_predict_batch(texts, qs, engine = engine, chunk_size = 256,
                                          progress = FALSE),
  check = FALSE, min_iterations = 3, filter_gc = FALSE
)
data.frame(method = as.character(chunks$expression),
           texts_per_second = round(length(texts) / as.numeric(chunks$median), 1))
#>             method texts_per_second
#> 1  chunk_size = 16              5.2
#> 2  chunk_size = 64              3.8
#> 3 chunk_size = 256              4.1
laya_engine_close(engine)
```

### Threads

``` r

threads <- c(1, 2, 4, parallel::detectCores())
by_threads <- do.call(rbind, lapply(threads, function(n) {
  e <- laya_engine("multilingual", intra_op_threads = n)
  on.exit(laya_engine_close(e))
  invisible(laya_predict(texts[1], qs, engine = e))
  t <- bench::mark(laya_predict_batch(texts[1:32], qs, engine = e, progress = FALSE),
                   min_iterations = 2, filter_gc = FALSE)
  data.frame(intra_op_threads = n, texts_per_second = round(32 / as.numeric(t$median), 1))
}))
by_threads
#>   intra_op_threads texts_per_second
#> 1                1              2.0
#> 2                2              3.5
#> 3                4              5.7
#> 4                8              5.2
```

The default, one thread per physical core, is usually the best setting.
Going past the physical cores, for example to
[`parallel::detectCores()`](https://rdrr.io/r/parallel/detectCores.html)
on a CPU with hyperthreading, adds no speed: the extra threads share
cores with the others, and with the ONNX Runtime build layaR downloads
they can make predictions much slower. On Windows and macOS,
`parallel::detectCores(logical = FALSE)` gives the number of physical
cores; on Linux it counts logical CPUs too, so check “Core(s) per
socket” in the output of `lscpu` instead.

### Asking several questions at once

All the questions about a text are answered in one forward pass, but
their instructions and options are part of the input, so each question
still adds tokens and time. Asking them together is cheaper than asking
them one by one:

``` r

engine <- laya_engine("multilingual")
invisible(laya_predict(texts[1], qs, engine = engine))
separately <- function() for (id in names(qs)) laya_predict(texts[1], qs[id], engine = engine)
n_questions <- bench::mark(
  `1 question` = laya_predict(texts[1], qs["churn_risk"], engine = engine),
  `3 questions, one call each` = separately(),
  `3 questions, one call` = laya_predict(texts[1], qs, engine = engine),
  `triage preset (5 questions)` = laya_predict(list(message = texts[1]), laya_preset("triage"),
                                               engine = engine),
  check = FALSE, min_iterations = 50
)
n_questions[, c("expression", "median")]
#> # A tibble: 4 × 2
#>   expression                    median
#>   <bch:expr>                  <bch:tm>
#> 1 1 question                    67.6ms
#> 2 3 questions, one call each   206.1ms
#> 3 3 questions, one call        168.9ms
#> 4 triage preset (5 questions)  486.5ms
laya_engine_close(engine)
```

Long option descriptions cost more than short ones: the triage preset’s
five questions carry more text than the three above.

## Summary

- Load an engine once (a few seconds, under a gigabyte of memory for the
  multilingual checkpoint) and reuse it; the default engine does this
  for you.
- The R layer adds no measurable time; the forward pass is the cost.
- On a CPU, one text per forward pass is fastest, and that is the
  default. Use
  [`laya_predict_batch()`](https://gueyenono.github.io/layaR/dev/reference/laya_predict.md)
  or
  [`laya_annotate()`](https://gueyenono.github.io/layaR/dev/reference/laya_annotate.md)
  for many texts anyway, for the progress bar and clean interrupts.
- Ask all your questions in one call, and keep option descriptions
  short.
- Use processes, not forks, for parallel work, and only when one engine
  isn’t enough.
