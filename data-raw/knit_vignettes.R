# Knits the precomputed vignettes. They need installed models (and a lot of
# time for the benchmarks), so CRAN and CI only see the knitted output:
#   vignettes/<name>.Rmd.orig  --knitr::knit()-->  vignettes/<name>.Rmd
# Website-only articles in vignettes/articles/ are knitted the same way.
# Run from the package root, after installing the current layaR:
#   Rscript data-raw/knit_vignettes.R [name ...]
# Each vignette is knitted in its own R process, so engines from one don't
# hold memory while the next runs.
args <- commandArgs(trailingOnly = TRUE)
origs <- Sys.glob(c("vignettes/*.Rmd.orig", "vignettes/articles/*.Rmd.orig"))
if (length(args)) origs <- origs[sub("\\.Rmd\\.orig$", "", basename(origs)) %in% args]
for (orig in origs) {
  out <- sub("\\.orig$", "", orig)
  message("Knitting ", orig)
  code <- sprintf(
    'setwd("%s"); knitr::knit("%s", output = "%s", quiet = TRUE, envir = globalenv())',
    dirname(orig), basename(orig), basename(out))
  status <- system2(file.path(R.home("bin"), "Rscript"), c("-e", shQuote(code)))
  if (status != 0) stop("Knitting ", orig, " failed")
}
