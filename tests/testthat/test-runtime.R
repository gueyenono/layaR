# ONNX Runtime discovery, download and loading. The install tests are
# offline: a fake NuGet package served through a file:// URL.

local_runtime_env <- function(env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  withr::local_envvar(R_USER_DATA_DIR = file.path(root, "data"), ORT_DYLIB_PATH = NA,
                      .local_envir = env)
  withr::local_options(layaR.onnxruntime = NULL, layaR.onnxruntime_url = NULL, .local_envir = env)
  root
}

# A zip laid out like the NuGet package, holding a placeholder library.
fake_nupkg <- function(root, entry) {
  skip_if(!nzchar(Sys.which("zip")), "no zip program")
  src <- file.path(root, "pkg")
  dir.create(file.path(src, dirname(entry)), recursive = TRUE)
  writeLines("not really a library", file.path(src, entry))
  zipfile <- file.path(root, "fake.nupkg")
  withr::with_dir(src, utils::zip(zipfile, entry, flags = "-q", zip = Sys.which("zip")))
  zipfile
}

file_url <- function(path) {
  path <- normalizePath(path, winslash = "/")
  paste0("file://", if (startsWith(path, "/")) "" else "/", path)
}

test_that("rs_file_sha512 hashes a file", {
  f <- withr::local_tempfile()
  writeBin(charToRaw("abc"), f)
  expect_identical(
    rs_unwrap(rs_file_sha512(f)),
    paste0("ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a",
           "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
  )
  expect_error(rs_unwrap(rs_file_sha512(file.path(tempdir(), "nope"))), class = "laya_error_io")
})

test_that("a failed load is a classed error and leaves nothing loaded", {
  skip_if(!is.null(rs_runtime_loaded()), "a runtime is already loaded in this session")
  local_runtime_env()
  bogus <- withr::local_tempfile()
  writeLines("not a library", bogus)
  withr::local_options(layaR.onnxruntime = bogus)
  expect_error(ensure_runtime(), class = "laya_error_runtime_load")
  expect_null(rs_runtime_loaded())
  # A library that isn't ONNX Runtime (layaR's own) is refused the same way.
  own <- getLoadedDLLs()[["layaR"]][["path"]]
  expect_error(rs_unwrap(rs_runtime_load(own)), "OrtGetApiBase", class = "laya_error_runtime_load")
  expect_null(rs_runtime_loaded())
})

test_that("the library is found by option, then ORT_DYLIB_PATH, then layaR's install", {
  skip_if(is.null(ort_platform()), "no official build for this platform")
  local_runtime_env()
  expect_null(runtime_resolve())
  own <- runtime_install_path()
  dir.create(dirname(own), recursive = TRUE)
  writeLines("lib", own)
  expect_identical(runtime_resolve()$source, "layaR")
  withr::local_envvar(ORT_DYLIB_PATH = "libonnxruntime-from-env")
  expect_identical(runtime_resolve(), list(path = "libonnxruntime-from-env", source = "ORT_DYLIB_PATH"))
  withr::local_options(layaR.onnxruntime = own)
  expect_identical(runtime_resolve(), list(path = normalizePath(own), source = "option"))
})

test_that("install_runtime extracts this platform's library", {
  root <- local_runtime_env()
  entry <- "runtimes/test-rid/native/libonnxruntime.so"
  pkg <- fake_nupkg(root, entry)
  dest <- file.path(root, "out", "libonnxruntime.so")
  dir.create(dirname(dest))
  install_runtime(file_url(pkg), rs_unwrap(rs_file_sha512(pkg)), entry, dest)
  expect_identical(readLines(dest), "not really a library")
  expect_false(dir.exists(file.path(dirname(dest), ".download")))

  expect_error(install_runtime(file_url(pkg), rs_unwrap(rs_file_sha512(pkg)),
                               "runtimes/other/native/x.so", dest),
               class = "laya_error_download")
})

test_that("a checksum mismatch installs nothing", {
  skip_if(is.null(ort_platform()), "no official build for this platform")
  root <- local_runtime_env()
  pkg <- fake_nupkg(root, ort_platform()$entry)
  withr::local_options(layaR.onnxruntime_url = file_url(pkg))
  expect_error(laya_install_runtime(ask = FALSE), "checksum", class = "laya_error_download")
  expect_false(file.exists(runtime_install_path()))
  expect_false(laya_runtime_info()$installed)
})

test_that("an installed runtime is kept unless overwrite = TRUE", {
  skip_if(is.null(ort_platform()), "no official build for this platform")
  local_runtime_env()
  own <- runtime_install_path()
  dir.create(dirname(own), recursive = TRUE)
  writeLines("lib", own)
  withr::local_options(layaR.onnxruntime_url = "file:///no/such/package.nupkg")
  expect_message(laya_install_runtime(ask = FALSE), "already installed")
  expect_true(laya_runtime_info()$installed)
})

test_that("platforms without an official build get a classed error", {
  local_runtime_env()
  local_mocked_bindings(ort_platform = function() NULL)
  expect_error(laya_install_runtime(ask = FALSE), class = "laya_error_runtime_not_found")
  expect_error(laya_install_runtime(ask = FALSE), "layaR.onnxruntime")
  expect_false(needs_runtime())
})

test_that("a missing runtime points to laya_install_runtime", {
  skip_if(!is.null(rs_runtime_loaded()), "a runtime is already loaded in this session")
  skip_if(is.null(ort_platform()), "no official build for this platform")
  local_runtime_env()
  local_mocked_bindings(is_interactive = function() FALSE)
  expect_error(ensure_runtime(), class = "laya_error_runtime_not_found")
  expect_error(ensure_runtime(), "laya_install_runtime")
})

test_that("a real library still loads after a failed attempt", {
  skip_if(!is.null(rs_runtime_loaded()), "a runtime is already loaded in this session")
  if (runtime_required() && needs_runtime()) laya_install_runtime(ask = FALSE)
  path <- runtime_resolve()$path
  skip_if(is.null(path) || !file.exists(path), "ONNX Runtime not installed")
  bogus <- withr::local_tempfile()
  writeLines("not a library", bogus)
  expect_false(rs_runtime_load(bogus)$ok)
  expect_true(rs_runtime_load(path)$ok)
  expect_identical(rs_runtime_loaded(), path)
})

test_that("the real runtime loads", {
  skip_without_runtime()
  info <- laya_runtime_info()
  expect_true(info$loaded)
  expect_true(utils::compareVersion(info$loaded_version, ort_min_version) >= 0)
  expect_type(info$build_info, "character")
  # Loading again reports the library already loaded.
  expect_identical(from_json(rs_unwrap(rs_runtime_load("ignored")))$path, info$loaded_path)
})
