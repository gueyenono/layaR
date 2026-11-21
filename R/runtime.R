# ONNX Runtime (plan 9.4). layaR is built with `ort`'s `load-dynamic`: the
# package doesn't contain ONNX Runtime, and loads the shared library at
# runtime, before the first engine. By default the library is Microsoft's
# official build, downloaded once from its NuGet package.

# Keep in sync with the `ort` crate in src/rust/Cargo.toml: ort 2.0.0-rc.13
# with api-27 needs ONNX Runtime >= 1.27. 1.28.0 is the version ort's own
# prebuilt binaries used before layaR switched to load-dynamic.
ort_version <- "1.28.0"
ort_min_version <- "1.27"
# SHA-512 of microsoft.ml.onnxruntime.1.28.0.nupkg, as published on nuget.org
# (base64 "2X2D0DH6dEzWfath6I3uzItsPBGxqYlRsPz3OFK7S9Tfk10McWdKGegNjT8KmOAtkSno3yTF9eo43mDvn9salw==").
ort_nupkg_sha512 <- paste0(
  "d97d83d031fa744cd67dab61e88deecc8b6c3c11b1a98951b0fcf73852bb4bd4",
  "df935d0c71674a19e80d8d3f0a98e02d9129e8df24c5f5ea38de60ef9fdb1a97"
)
ort_nupkg_size_mb <- 139

# The library inside the NuGet package for this platform, or NULL when
# Microsoft ships none (Intel Macs, 32-bit systems, ...).
ort_platform <- function() {
  sys <- Sys.info()[["sysname"]]
  arch <- R.version$arch
  rid <- if (sys == "Linux" && arch == "x86_64") "linux-x64"
    else if (sys == "Linux" && arch %in% c("aarch64", "arm64")) "linux-arm64"
    else if (sys == "Darwin" && arch %in% c("aarch64", "arm64")) "osx-arm64"
    else if (sys == "Windows" && arch == "x86_64") "win-x64"
    else return(NULL)
  lib <- switch(sys, Linux = "libonnxruntime.so", Darwin = "libonnxruntime.dylib",
                Windows = "onnxruntime.dll")
  list(rid = rid, lib = lib, entry = paste0("runtimes/", rid, "/native/", lib))
}

runtime_url <- function() {
  getOption("layaR.onnxruntime_url", sprintf(
    "https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/%1$s/microsoft.ml.onnxruntime.%1$s.nupkg",
    ort_version
  ))
}

runtime_dir <- function() {
  file.path(tools::R_user_dir("layaR", "data"), "onnxruntime", ort_version)
}

# Where laya_install_runtime() puts the library (NA on unsupported platforms).
runtime_install_path <- function(platform = ort_platform()) {
  if (is.null(platform)) return(NA_character_)
  file.path(runtime_dir(), platform$lib)
}

# The library to load: the layaR.onnxruntime option, then ORT_DYLIB_PATH,
# then layaR's own install. NULL when there is none.
runtime_resolve <- function() {
  opt <- getOption("layaR.onnxruntime")
  if (!is.null(opt) && nzchar(opt)) return(list(path = expand_lib_path(opt), source = "option"))
  env <- Sys.getenv("ORT_DYLIB_PATH")
  if (nzchar(env)) return(list(path = expand_lib_path(env), source = "ORT_DYLIB_PATH"))
  own <- runtime_install_path()
  if (!is.na(own) && file.exists(own)) return(list(path = normalizePath(own), source = "layaR"))
  NULL
}

# An existing file becomes an absolute path; a bare library name is left for
# the dynamic linker to find.
expand_lib_path <- function(path) {
  path <- path.expand(path)
  if (file.exists(path)) normalizePath(path) else path
}

#' Install ONNX Runtime
#'
#' layaR runs models on [ONNX Runtime](https://onnxruntime.ai), which it loads
#' when the first engine is created rather than building it in. On first use
#' layaR downloads Microsoft's official build (version 1.28.0, MIT license)
#' from its NuGet package `Microsoft.ML.OnnxRuntime` (about 139 MB, checked
#' against the SHA-512 that nuget.org publishes) and keeps only this
#' platform's library (about 25 MB) in `tools::R_user_dir("layaR", "data")`.
#' [laya_download_model()] does this for you; call `laya_install_runtime()`
#' to do it on its own, for example before going offline.
#'
#' Microsoft publishes builds for Linux (x86_64 and arm64), macOS on Apple
#' silicon and Windows (x64). Elsewhere, Intel Macs included, install ONNX
#' Runtime 1.27 or newer yourself and point layaR at the library with
#' `options(layaR.onnxruntime = "/path/to/libonnxruntime.dylib")` or the
#' `ORT_DYLIB_PATH` environment variable. Either one also overrides the
#' downloaded library on supported platforms.
#'
#' The library is loaded once per R session. To switch to another one,
#' restart R.
#'
#' @param overwrite Download again even if the library is installed?
#' @param ask Ask for confirmation before downloading? Defaults to `TRUE` in
#'   interactive sessions.
#' @return `laya_install_runtime()` returns the library's path, invisibly.
#'   `laya_runtime_info()` returns a list: the `version` layaR installs, the
#'   `path` and `source` (`"option"`, `"ORT_DYLIB_PATH"` or `"layaR"`) of the
#'   library it would load, whether layaR's own copy is `installed`, whether
#'   a library is `loaded`, and, once loaded, its `loaded_path`,
#'   `loaded_version` and ONNX Runtime's `build_info`.
#' @seealso [laya_download_model()]
#' @examples
#' laya_runtime_info()
#' \dontrun{
#' laya_install_runtime()
#' }
#' @export
laya_install_runtime <- function(overwrite = FALSE, ask = interactive()) {
  platform <- ort_platform()
  if (is.null(platform)) abort_runtime_unsupported()
  dest <- runtime_install_path(platform)
  if (file.exists(dest) && !isTRUE(overwrite)) {
    cli::cli_inform(c(v = "ONNX Runtime {ort_version} is already installed at {.path {dest}}."))
    return(invisible(dest))
  }
  loaded <- rs_runtime_loaded()
  if (!is.null(loaded) && file.exists(dest) && identical(normalizePath(loaded), normalizePath(dest))) {
    laya_abort(c("ONNX Runtime is loaded from {.path {dest}}, so it can't be replaced now.",
                 i = "Restart R, then run {.code laya_install_runtime(overwrite = TRUE)}."),
               kind = "io")
  }
  if (isTRUE(ask)) {
    ok <- utils::askYesNo(sprintf(
      "Download ONNX Runtime %s (%d MB, from Microsoft's NuGet package) to %s?",
      ort_version, ort_nupkg_size_mb, dirname(dest)
    ))
    if (!isTRUE(ok)) {
      cli::cli_inform("Download cancelled.")
      return(invisible(NULL))
    }
  }
  install_runtime(runtime_url(), ort_nupkg_sha512, platform$entry, dest)
  cli::cli_inform(c(v = "Installed ONNX Runtime {ort_version} at {.path {dest}}."))
  invisible(dest)
}

# Download the package, check its hash, extract `entry` to `dest`.
install_runtime <- function(url, sha512, entry, dest, call = parent.frame()) {
  staging <- file.path(dirname(dest), ".download")
  dir.create(staging, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(staging, recursive = TRUE), add = TRUE)
  pkg <- file.path(staging, "onnxruntime.nupkg")
  res <- curl::multi_download(url, pkg, resume = TRUE, progress = interactive())
  if (!res$success || !(res$status_code %in% c(0L, 200L, 206L, 416L))) {
    why <- if (is.na(res$error)) paste("HTTP", res$status_code) else res$error
    laya_abort(c("Download of ONNX Runtime failed.", set_names_x(why),
                 i = "Run {.fn laya_install_runtime} again to retry."),
               kind = "download", call = call)
  }
  got <- rs_unwrap(rs_file_sha512(pkg), call = call)
  if (!identical(got, sha512)) {
    laya_abort(c("The ONNX Runtime download from {.url {url}} doesn't match its published checksum.",
                 i = "Nothing was installed. Run {.fn laya_install_runtime} again to retry."),
               kind = "download", call = call)
  }
  out <- tryCatch(
    utils::unzip(pkg, files = entry, exdir = staging, junkpaths = TRUE),
    warning = function(w) character(), error = function(e) character()
  )
  if (length(out) != 1 || !file.exists(out)) {
    laya_abort("The ONNX Runtime package has no {.file {entry}}.", kind = "download", call = call)
  }
  if (file.exists(dest)) unlink(dest)
  if (!file.rename(out, dest)) {
    laya_abort("Couldn't move ONNX Runtime to {.path {dest}}.", kind = "io", call = call)
  }
  invisible(dest)
}

abort_runtime_unsupported <- function(call = parent.frame()) {
  laya_abort(c(
    "Microsoft publishes no ONNX Runtime build for this platform ({R.version$platform}).",
    i = "Install ONNX Runtime {ort_min_version} or newer yourself, then point layaR at the library:",
    " " = "{.code options(layaR.onnxruntime = \"/path/to/libonnxruntime.dylib\")} or the {.envvar ORT_DYLIB_PATH} environment variable."
  ), kind = "runtime_not_found", call = call)
}

# Make sure ONNX Runtime is loaded before an engine is created: find the
# library (offering to download it in interactive sessions) and load it.
ensure_runtime <- function(call = parent.frame()) {
  loaded <- rs_runtime_loaded()
  if (!is.null(loaded)) {
    wanted <- runtime_resolve()
    if (!is.null(wanted) && !same_lib(wanted$path, loaded) && !isTRUE(the$runtime_warned)) {
      the$runtime_warned <- TRUE
      cli::cli_warn(c(
        "ONNX Runtime is already loaded from {.path {loaded}}; {.path {wanted$path}} is ignored.",
        i = "Restart R to switch libraries."
      ), class = "laya_warning")
    }
    return(invisible(loaded))
  }
  found <- runtime_resolve()
  if (is.null(found)) {
    if (is.null(ort_platform())) abort_runtime_unsupported(call = call)
    if (is_interactive()) laya_install_runtime(ask = TRUE)
    found <- runtime_resolve()
    if (is.null(found)) {
      laya_abort(c(
        "layaR needs ONNX Runtime, which isn't installed yet.",
        i = "Install it with {.run layaR::laya_install_runtime()} (a one-time {ort_nupkg_size_mb} MB download)."
      ), kind = "runtime_not_found", call = call)
    }
  }
  res <- rs_runtime_load(found$path)
  if (!isTRUE(res$ok)) {
    msg <- res$error_message
    hint <- if (.Platform$OS.type == "windows") {
      c(i = "ONNX Runtime needs the Microsoft Visual C++ Redistributable (x64); install it if it's missing.")
    }
    src <- switch(found$source, option = "the {.code layaR.onnxruntime} option",
                  ORT_DYLIB_PATH = "{.envvar ORT_DYLIB_PATH}", "layaR's install")
    laya_abort(c(
      paste0("Couldn't load ONNX Runtime from ", src, "."),
      x = "{msg}",
      hint,
      i = "layaR needs ONNX Runtime {ort_min_version} or newer; see {.fn laya_install_runtime}."
    ), kind = res$error_kind, call = call)
  }
  invisible(found$path)
}

# A seam for tests.
is_interactive <- function() interactive()

same_lib <- function(a, b) {
  identical(normalizePath(a, mustWork = FALSE), normalizePath(b, mustWork = FALSE))
}

#' @rdname laya_install_runtime
#' @export
laya_runtime_info <- function() {
  found <- runtime_resolve()
  own <- runtime_install_path()
  loaded <- rs_runtime_loaded()
  build_info <- loaded_version <- NA_character_
  if (!is.null(loaded)) {
    res <- rs_runtime_load(loaded)
    if (isTRUE(res$ok)) {
      details <- from_json(res$value)
      build_info <- details$build_info
      if (nzchar(details$version)) loaded_version <- details$version
    }
  }
  list(
    version = ort_version,
    path = if (is.null(found)) own else found$path,
    source = if (is.null(found)) NA_character_ else found$source,
    installed = !is.na(own) && file.exists(own),
    loaded = !is.null(loaded),
    loaded_path = loaded %||% NA_character_,
    loaded_version = loaded_version,
    build_info = build_info
  )
}
