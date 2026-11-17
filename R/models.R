# Model management (plan 7.7): where exported checkpoints live, and getting
# them there by download or import.

#' Where models live
#'
#' layaR keeps exported checkpoints in a model root folder with one subfolder
#' per checkpoint (`multilingual/`, `english/`, `typed-decisions/`). The root
#' is, in order: the `layaR.model_root` option, the `LAYA_ONNX_ROOT`
#' environment variable (shared with Laya's Rust SDK), or the user cache
#' folder `tools::R_user_dir("layaR", "cache")` plus `onnx/`. Downloads and
#' imports go there.
#'
#' When a checkpoint isn't in the model root, layaR also looks in the cache
#' that Laya's other SDKs share (`~/.cache/laya/onnx`, or
#' `%LOCALAPPDATA%/laya/onnx` on Windows), so a model exported or downloaded
#' for the Rust or TypeScript SDK is reused. layaR never writes there. Set
#' `options(layaR.shared_cache = FALSE)` to turn this off.
#'
#' @param checkpoint A checkpoint name.
#' @return `laya_model_root()` and `laya_model_path()` return paths (the
#'   latter is where layaR installs `checkpoint`); `laya_model_available()`
#'   returns `TRUE` when a complete export is found in either place.
#' @seealso [laya_models()], [laya_download_model()], [laya_import_model()]
#' @examples
#' laya_model_root()
#' laya_model_path("english")
#' laya_model_available()
#' @export
laya_model_root <- function() {
  root <- getOption("layaR.model_root")
  if (is.null(root) || !nzchar(root)) root <- Sys.getenv("LAYA_ONNX_ROOT")
  if (!nzchar(root)) root <- file.path(tools::R_user_dir("layaR", "cache"), "onnx")
  normalizePath(path.expand(root), mustWork = FALSE)
}

#' @rdname laya_model_root
#' @export
laya_model_path <- function(checkpoint = c("multilingual", "english", "typed-decisions")) {
  checkpoint <- match.arg(checkpoint)
  file.path(laya_model_root(), checkpoint)
}

#' @rdname laya_model_root
#' @export
laya_model_available <- function(checkpoint = getOption("layaR.checkpoint", "multilingual")) {
  checkpoint <- match.arg(checkpoint, checkpoints)
  !is.null(find_model(checkpoint))
}

# The shared cross-SDK cache, read-only (laya-rust's default cache root).
shared_model_root <- function() {
  if (!isTRUE(getOption("layaR.shared_cache", TRUE))) return(NULL)
  if (.Platform$OS.type == "windows" && nzchar(Sys.getenv("LOCALAPPDATA"))) {
    return(file.path(Sys.getenv("LOCALAPPDATA"), "laya", "onnx"))
  }
  file.path(path.expand("~"), ".cache", "laya", "onnx")
}

# The first complete export of `checkpoint`: layaR's root, then the shared cache.
find_model <- function(checkpoint) {
  candidates <- c(laya_model_path(checkpoint),
                  if (!is.null(root <- shared_model_root())) file.path(root, checkpoint))
  for (dir in candidates) if (rs_artifacts_complete(dir)) return(dir)
  NULL
}

abort_no_model <- function(checkpoint, call = parent.frame()) {
  laya_abort(c(
    "No {.val {checkpoint}} model found in {.path {laya_model_root()}}.",
    i = "Download one with {.run layaR::laya_download_model(\"{checkpoint}\")} (about 1.3 GB),",
    " " = "or import an export with {.fn laya_import_model}.",
    i = "See {.fn laya_model_root} for where layaR looks."
  ), kind = "model_not_found", call = call)
}

#' List checkpoints and whether they are installed
#'
#' @return A data frame with one row per checkpoint: `checkpoint`,
#'   `installed`, `path` (where it was found, or where it would be installed),
#'   `source` (`"layaR"` for the model root, `"shared"` for the cross-SDK
#'   cache, `NA` when not installed), `layout` (`"fused"` or `"split"`) and
#'   `size_gb`.
#' @examples
#' laya_models()
#' @export
laya_models <- function() {
  rows <- lapply(checkpoints, function(ck) {
    found <- find_model(ck)
    path <- found %||% laya_model_path(ck)
    data.frame(
      checkpoint = ck,
      installed = !is.null(found),
      path = path,
      source = if (is.null(found)) NA_character_
               else if (identical(found, laya_model_path(ck))) "layaR" else "shared",
      layout = if (is.null(found)) NA_character_ else model_layout(found),
      size_gb = if (is.null(found)) NA_real_ else round(dir_size(found) / 1e9, 2),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

model_layout <- function(dir) {
  if (file.exists(file.path(dir, "model.onnx"))) "fused"
  else if (file.exists(file.path(dir, "encoder.onnx"))) "split"
  else NA_character_
}

dir_size <- function(dir) {
  files <- list.files(dir, recursive = TRUE, full.names = TRUE)
  sum(file.size(files), na.rm = TRUE)
}

# ---- download ----

# laya-rust's artifact lists (model_artifacts.rs): remote path -> local path.
fused_files <- c(
  "model.onnx" = "model.onnx",
  "model.onnx.data" = "model.onnx.data",
  "rl_agent_config.json" = "rl_agent_config.json",
  "tokenizer/tokenizer.json" = "tokenizer/tokenizer.json",
  "tokenizer/tokenizer_config.json" = "tokenizer/tokenizer_config.json"
)
split_files <- c(
  "encoder.onnx" = "encoder.onnx",
  "encoder.onnx.data" = "encoder.onnx.data",
  "head.onnx" = "head.onnx",
  "head.onnx.data" = "head.onnx.data",
  "rl_agent_config.json" = "rl_agent_config.json",
  "tokenizer.json" = "tokenizer.json"
)
optional_split_files <- c("encoder.onnx.data", "head.onnx.data")

# Where each checkpoint sits in the upstream Hugging Face repository; the
# English checkpoint is at the repository root.
hf_subfolder <- function(checkpoint) {
  switch(checkpoint, english = "", checkpoint)
}

#' Download a model
#'
#' Downloads an exported ONNX checkpoint (about 1.3 GB) from a Hugging Face
#' repository into [laya_model_path()]. Files go to a staging folder first,
#' so an interrupted download resumes where it stopped on the next call and
#' a partial download is never mistaken for a model.
#'
#' The Laya authors publish PyTorch weights, not ONNX exports, so until an
#' ONNX export is published the download fails with a
#' `laya_error_model_not_published` error that explains how to export one
#' and add it with [laya_import_model()].
#'
#' @param checkpoint Which checkpoint to download.
#' @param repo The Hugging Face repository, `"owner/name"`. Defaults to the
#'   `layaR.model_repo` option, or the upstream `"convaiinnovations/laya"`.
#' @param revision Branch, tag or commit of the repository.
#' @param subfolder Folder of the checkpoint inside the repository. `NULL`
#'   uses the upstream layout (`multilingual/`, `typed-decisions/`, and the
#'   repository root for `english`).
#' @param token A Hugging Face access token for private or gated
#'   repositories; defaults to the `HF_TOKEN` environment variable. The
#'   `HF_ENDPOINT` environment variable changes the server, as in other
#'   Hugging Face tools.
#' @param overwrite Replace an installed model?
#' @param ask Ask for confirmation before downloading? Defaults to `TRUE` in
#'   interactive sessions.
#' @return The model's path, invisibly.
#' @seealso [laya_models()], [laya_import_model()]
#' @examples
#' \dontrun{
#' laya_download_model("multilingual")
#' }
#' @export
laya_download_model <- function(checkpoint = c("multilingual", "english", "typed-decisions"),
                                repo = getOption("layaR.model_repo", "convaiinnovations/laya"),
                                revision = "main", subfolder = NULL,
                                token = Sys.getenv("HF_TOKEN"), overwrite = FALSE,
                                ask = interactive()) {
  checkpoint <- match.arg(checkpoint)
  dest <- laya_model_path(checkpoint)
  if (rs_artifacts_complete(dest) && !isTRUE(overwrite)) {
    cli::cli_inform(c(v = "The {.val {checkpoint}} model is already installed at {.path {dest}}.",
                      i = "Use {.code overwrite = TRUE} to download it again."))
    return(invisible(dest))
  }
  subfolder <- subfolder %||% hf_subfolder(checkpoint)
  endpoint <- sub("/+$", "", Sys.getenv("HF_ENDPOINT", "https://huggingface.co"))
  base <- paste0(paste(c(endpoint, repo, "resolve", revision, if (nzchar(subfolder)) subfolder),
                       collapse = "/"), "/")
  headers <- if (nzchar(token)) paste("Authorization: Bearer", token) else NULL

  files <- if (remote_exists(paste0(base, "model.onnx"), headers)) {
    fused_files
  } else if (remote_exists(paste0(base, "encoder.onnx"), headers) &&
             remote_exists(paste0(base, "head.onnx"), headers)) {
    keep <- !names(split_files) %in% optional_split_files |
      vapply(paste0(base, names(split_files)), remote_exists, logical(1), headers = headers)
    split_files[keep]
  } else {
    laya_abort(c(
      "{.val {repo}} has no ONNX export of the {.val {checkpoint}} checkpoint at {.url {base}}.",
      i = "The Laya authors publish PyTorch weights, which layaR can't load directly.",
      i = "Export the model once with Laya's {.file export_onnx.py} (see the layaR README),",
      " " = "then add it with {.code laya_import_model(\"path/to/export\", \"{checkpoint}\")}."
    ), kind = "model_not_published")
  }

  if (isTRUE(ask)) {
    ok <- utils::askYesNo(sprintf("Download the %s model (about 1.3 GB) from %s to %s?",
                                  checkpoint, repo, dest))
    if (!isTRUE(ok)) {
      cli::cli_inform("Download cancelled.")
      return(invisible(NULL))
    }
  }

  root <- laya_model_root()
  staging <- file.path(root, paste0(".download-", checkpoint))
  local <- file.path(staging, unname(files))
  for (d in unique(dirname(local))) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  args <- list(urls = paste0(base, names(files)), destfiles = local, resume = TRUE,
               progress = interactive())
  if (!is.null(headers)) args$httpheader <- headers
  res <- do.call(curl::multi_download, args)
  failed <- !res$success | !(res$status_code %in% c(0L, 200L, 206L, 416L))
  if (any(failed)) {
    why <- ifelse(is.na(res$error), paste("HTTP", res$status_code), res$error)[failed]
    laya_abort(c(
      "Download of the {.val {checkpoint}} model failed.",
      set_names_x(sprintf("%s: %s", basename(res$url[failed]), why)),
      i = "Run {.fn laya_download_model} again to resume."
    ), kind = "download")
  }
  if (!rs_artifacts_complete(staging)) {
    laya_abort("The downloaded files don't form a complete model in {.path {staging}}.",
               kind = "download")
  }
  if (dir.exists(dest) || is_symlink(dest)) remove_model_dir(dest)
  if (!file.rename(staging, dest)) {
    laya_abort("Couldn't move the download from {.path {staging}} to {.path {dest}}.",
               kind = "io")
  }
  cli::cli_inform(c(v = "Installed the {.val {checkpoint}} model at {.path {dest}}."))
  invisible(dest)
}

remote_exists <- function(url, headers = NULL) {
  h <- curl::new_handle(nobody = TRUE, followlocation = TRUE, failonerror = FALSE)
  if (!is.null(headers)) curl::handle_setopt(h, httpheader = headers)
  res <- tryCatch(curl::curl_fetch_memory(url, handle = h), error = function(e) NULL)
  !is.null(res) && (res$status_code == 0L || (res$status_code >= 200L && res$status_code < 400L))
}

# Bullets for cli, with braces escaped so cli doesn't interpolate them.
set_names_x <- function(x) {
  x <- gsub("}", "}}", gsub("{", "{{", x, fixed = TRUE), fixed = TRUE)
  stats::setNames(x, rep("x", length(x)))
}

#' Import an exported model
#'
#' Adds a checkpoint exported with Laya's `export_onnx.py` (or downloaded by
#' another tool) to layaR's model root, so [laya_engine()] finds it by name.
#'
#' @param path The export's folder: it holds `model.onnx` (or `encoder.onnx`
#'   and `head.onnx`), `rl_agent_config.json` and the tokenizer.
#' @param checkpoint Which checkpoint the export is.
#' @param method `"symlink"` (the default) links to the folder without
#'   copying 1.3 GB; `"copy"` copies it, so the original can be deleted.
#' @param overwrite Replace an installed model?
#' @return The installed path, invisibly.
#' @examples
#' \dontrun{
#' laya_import_model("~/exports/onnx/multilingual", "multilingual")
#' }
#' @export
laya_import_model <- function(path, checkpoint = c("multilingual", "english", "typed-decisions"),
                              method = c("symlink", "copy"), overwrite = FALSE) {
  checkpoint <- match.arg(checkpoint)
  method <- match.arg(method)
  if (!is.character(path) || length(path) != 1 || is.na(path)) {
    laya_abort("{.arg path} must be a single folder path.", kind = "invalid_argument")
  }
  path <- normalizePath(path.expand(path), mustWork = FALSE)
  if (!rs_artifacts_complete(path)) {
    laya_abort(c(
      "{.path {path}} isn't a complete model export.",
      i = "It needs {.file model.onnx} (or {.file encoder.onnx} and {.file head.onnx}), {.file rl_agent_config.json} and the tokenizer."
    ), kind = "artifacts_not_found")
  }
  dest <- laya_model_path(checkpoint)
  if (identical(dest, path)) return(invisible(dest))
  if (is_symlink(dest) && identical(normalizePath(dest, mustWork = FALSE), path) && !isTRUE(overwrite)) {
    cli::cli_inform(c(v = "{.path {path}} is already imported as the {.val {checkpoint}} model."))
    return(invisible(dest))
  }
  if (dir.exists(dest) || is_symlink(dest)) {
    if (!isTRUE(overwrite)) {
      laya_abort(c("A {.val {checkpoint}} model is already installed at {.path {dest}}.",
                   i = "Use {.code overwrite = TRUE} to replace it."), kind = "model_exists")
    }
    close_cached_engine(checkpoint)
    remove_model_dir(dest)
  }
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  ok <- if (method == "symlink") {
    file.symlink(path, dest)
  } else {
    dir.create(dest)
    all(file.copy(list.files(path, full.names = TRUE, all.files = FALSE), dest, recursive = TRUE))
  }
  if (!isTRUE(ok) || !rs_artifacts_complete(dest)) {
    laya_abort("Couldn't {method} {.path {path}} to {.path {dest}}.", kind = "io")
  }
  cli::cli_inform(c(v = "Imported the {.val {checkpoint}} model ({method}) at {.path {dest}}."))
  invisible(dest)
}

#' Remove an installed model
#'
#' Deletes a checkpoint from layaR's model root, freeing about 1.3 GB. A
#' model imported as a symlink only loses the link. Models in the shared
#' cross-SDK cache are never touched.
#'
#' @param checkpoint Which checkpoint to remove.
#' @param ask Ask for confirmation first? Defaults to `TRUE` in interactive
#'   sessions.
#' @return `TRUE` if a model was removed, invisibly.
#' @examples
#' \dontrun{
#' laya_remove_model("english")
#' }
#' @export
laya_remove_model <- function(checkpoint = c("multilingual", "english", "typed-decisions"),
                              ask = interactive()) {
  checkpoint <- match.arg(checkpoint)
  dest <- laya_model_path(checkpoint)
  if (!dir.exists(dest) && !is_symlink(dest)) {
    cli::cli_inform("No {.val {checkpoint}} model in {.path {laya_model_root()}}.")
    return(invisible(FALSE))
  }
  if (isTRUE(ask) && !isTRUE(utils::askYesNo(sprintf("Delete the %s model at %s?", checkpoint, dest)))) {
    return(invisible(FALSE))
  }
  close_cached_engine(checkpoint)
  remove_model_dir(dest)
  cli::cli_inform(c(v = "Removed the {.val {checkpoint}} model."))
  invisible(TRUE)
}

# Sys.readlink() gives "" for a regular file and NA for a missing path.
is_symlink <- function(path) {
  link <- Sys.readlink(path)
  !is.na(link) && nzchar(link)
}

# A symlinked import loses only the link, never the files it points at.
remove_model_dir <- function(dir) {
  if (is_symlink(dir)) file.remove(dir) else unlink(dir, recursive = TRUE)
}

close_cached_engine <- function(checkpoint) {
  eng <- the$engines[[checkpoint]]
  if (!is.null(eng)) laya_engine_close(eng)
}
