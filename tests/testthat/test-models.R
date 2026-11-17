# Model management, offline: a fake Hugging Face repository served through
# file:// URLs (HF_ENDPOINT), and placeholder files instead of real weights
# (the completeness check only looks at file names).

fake_export <- function(dir, layout = c("fused", "split")) {
  layout <- match.arg(layout)
  files <- if (layout == "fused") unname(fused_files) else c("encoder.onnx", "head.onnx",
                                                             "rl_agent_config.json", "tokenizer.json")
  for (f in file.path(dir, files)) {
    dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
    writeLines("placeholder", f)
  }
  dir
}

local_model_env <- function(env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  withr::local_options(layaR.model_root = file.path(root, "models"), layaR.shared_cache = FALSE,
                       .local_envir = env)
  root
}

test_that("laya_models lists checkpoints and where they are", {
  root <- local_model_env()
  m <- laya_models()
  expect_identical(m$checkpoint, c("multilingual", "english", "typed-decisions"))
  expect_false(any(m$installed))
  fake_export(laya_model_path("english"))
  m <- laya_models()
  expect_identical(m$installed, c(FALSE, TRUE, FALSE))
  expect_identical(m$source[[2]], "layaR")
  expect_identical(m$layout[[2]], "fused")
})

test_that("the shared cross-SDK cache is read, never written", {
  root <- local_model_env()
  home <- file.path(root, "home")
  withr::local_envvar(HOME = home, LOCALAPPDATA = file.path(root, "appdata"))
  withr::local_options(layaR.shared_cache = TRUE)
  shared <- file.path(shared_model_root(), "multilingual")
  fake_export(shared, "split")
  expect_true(laya_model_available("multilingual"))
  m <- laya_models()
  expect_identical(m$source[[1]], "shared")
  expect_identical(m$layout[[1]], "split")
  expect_identical(normalizePath(m$path[[1]]), normalizePath(shared))
  withr::local_options(layaR.shared_cache = FALSE)
  expect_false(laya_model_available("multilingual"))
})

test_that("a missing model points to download and import", {
  local_model_env()
  expect_error(laya_engine("english"), class = "laya_error_model_not_found")
  expect_error(laya_engine("english"), "laya_download_model")
})

test_that("laya_import_model links or copies an export", {
  root <- local_model_env()
  src <- fake_export(file.path(root, "export"))
  expect_message(dest <- laya_import_model(src, "english"), "Imported")
  expect_true(nzchar(Sys.readlink(dest)))
  expect_true(laya_model_available("english"))
  expect_message(laya_import_model(src, "english"), "already imported")
  other <- fake_export(file.path(root, "other-export"))
  expect_error(laya_import_model(other, "english"), class = "laya_error_model_exists")

  # Removing a symlinked import keeps the original files.
  expect_message(laya_remove_model("english", ask = FALSE), "Removed")
  expect_true(file.exists(file.path(src, "model.onnx")))
  expect_false(laya_model_available("english"))

  expect_message(dest <- laya_import_model(src, "english", method = "copy"), "copy")
  expect_false(nzchar(Sys.readlink(dest)))
  expect_true(file.exists(file.path(dest, "tokenizer", "tokenizer.json")))
  expect_message(laya_import_model(src, "english", method = "copy", overwrite = TRUE), "Imported")

  expect_error(laya_import_model(file.path(root, "nope"), "english"),
               class = "laya_error_artifacts_not_found")
})

test_that("laya_download_model fetches a published export", {
  root <- local_model_env()
  server <- file.path(root, "hf")
  withr::local_envvar(HF_ENDPOINT = paste0("file://", server))
  # The upstream layout: checkpoints in subfolders, english at the root.
  fake_export(file.path(server, "me/laya-onnx/resolve/main/multilingual"))
  fake_export(file.path(server, "me/laya-onnx/resolve/main"), "split")

  expect_message(dest <- laya_download_model("multilingual", repo = "me/laya-onnx", ask = FALSE),
                 "Installed")
  expect_identical(normalizePath(dest), normalizePath(laya_model_path("multilingual")))
  expect_true(laya_model_available("multilingual"))
  expect_false(dir.exists(file.path(laya_model_root(), ".download-multilingual")))
  expect_message(laya_download_model("multilingual", repo = "me/laya-onnx", ask = FALSE),
                 "already installed")

  # Split layout; the optional .data files are skipped when absent.
  laya_download_model("english", repo = "me/laya-onnx", ask = FALSE) |> expect_message("Installed")
  expect_identical(laya_models()$layout[[2]], "split")
})

test_that("an unpublished model gives a classed error with next steps", {
  root <- local_model_env()
  withr::local_envvar(HF_ENDPOINT = paste0("file://", file.path(root, "empty")))
  expect_error(laya_download_model("multilingual", repo = "nobody/nothing", ask = FALSE),
               class = "laya_error_model_not_published")
  expect_error(laya_download_model("multilingual", repo = "nobody/nothing", ask = FALSE),
               "laya_import_model")
})
