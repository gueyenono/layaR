# Draft upstream issues for NandhaKishorM/laya

*Drafted 2026-11-15. Not posted. Both follow the repo's `feature_request.yml` template (title
prefix `[feature]: `, label `enhancement`). Before drafting, I searched existing issues for "onnx",
"load-dynamic", "download-binaries" and "windows-gnu": neither request exists. Related issues:
#674 (Rust SDK, closed) and #37 (GGUF / no-dep executable, open).*

---

## Issue U1 — Publish the ONNX exports on Hugging Face

**Posted 2026-11-16 as https://github.com/NandhaKishorM/laya/issues/1504** (without the `enhancement` label; only maintainers can set labels).

**Title:** `[feature]: publish the ONNX exports of the three checkpoints on Hugging Face`

### The problem

`laya-onnx` (laya-rust), the .NET SDK and laya-ts all run on ONNX Runtime, but none of the Hugging
Face repos ships ONNX files today. `convaiinnovations/laya`, `laya-multilingual` and
`laya-typed-decisions` hold only `model.safetensors`, configs and tokenizers. So the first step for
any non-Python user is a Python + PyTorch (>= 2.9) environment, about 2.5 GB of disk per
checkpoint, and `laya-rust/tools/export_onnx.py`. That undercuts the main appeal of the ONNX SDKs,
which is that no Python is needed. `laya-rust/MODELS.md` §6 already notes that
`allow_download = true` returns 404 until the files are uploaded.

I'm building an R package on top of `laya-onnx` (via extendr), and this export step is the biggest
setup hurdle for R users.

### Proposed solution

Upload the fused export that `export_onnx.py` produces, in the layout `ModelArtifacts::resolve`
already downloads (`model.onnx`, `model.onnx.data`, `rl_agent_config.json`,
`tokenizer/tokenizer.json`, `tokenizer/tokenizer_config.json`):

- `convaiinnovations/laya` at the bundle root (English, subfolder `""`);
- `convaiinnovations/laya` under `multilingual/` and `typed-decisions/`.

These are the URLs the Rust crate already builds
(`https://huggingface.co/<repo>/resolve/main/<subfolder>/<file>`), so once the files exist,
`allow_download` works with no code changes. If the files go elsewhere (an `onnx/` subfolder, or a
separate repo such as `convaiinnovations/laya-onnx`), a one-line change to the URL construction
would follow.

Pinning a revision for the ONNX files, as #332 did for the PyTorch weights, would let downstream
packages verify what they download.

### Alternatives considered

- Every user exports locally. This works, but needs Python and torch, which is the thing the ONNX
  SDKs exist to avoid.
- Downstream re-hosting. The checkpoints are Apache-2.0, so I could host exports myself for the R
  package. I'd much rather point at an official source, so there's one canonical artifact per
  checkpoint and nobody has to trust a third-party conversion.

### Use case

```r
# R, once exports are published
laya_download_model("multilingual")
laya_predict("We were billed twice for March.", laya_preset("triage"))
```

The same applies to `cargo add laya-onnx` users, the .NET SDK and laya-ts.

### Prior art

`laya-rust/MODELS.md` §6 ("Downloading (future, once published)") and §8.

---

## Issue U2 — Let downstream crates choose how `laya-onnx` links ONNX Runtime

**Title:** `[feature]: laya-onnx: expose ort's load-dynamic (make download-binaries an optional default feature)`

> **Recommendation:** post this after Phase 0, once a Windows build of the R prototype has run.
> The Windows/GNU failure described below is what I expect, but I haven't confirmed it yet. If it
> does fail, add the exact error output to "The problem". The request stands either way because
> of CRAN, but a real error log makes it more convincing.

### The problem

`laya-onnx` depends on `ort = "2.0.0-rc.13"` with ort's default features, which include
`download-binaries`: a prebuilt ONNX Runtime is fetched **at build time**. Cargo feature
unification means a downstream crate can add ort features but can't remove ones the dependency
enables. So anyone embedding `laya-onnx` is locked into build-time downloads.

That blocks two embedding scenarios:

1. **CRAN (R) and similar offline build farms** forbid network access during package builds.
2. **Windows with the GNU toolchain** (`x86_64-pc-windows-gnu`, which R uses via Rtools). ort's
   prebuilt binaries target MSVC. *[Replace with the observed error after testing.]*

ort already supports both cases through `load-dynamic`: the library is loaded at runtime from a
path. That's how the CRAN `torch` package handles libtorch, and it's the pattern I'd use for the R
package (download the official ONNX Runtime release on first use).

### Proposed solution

Make ort's linking strategy a `laya-onnx` feature, with today's behavior as the default:

```toml
[dependencies]
ort = { version = "2.0.0-rc.13", default-features = false, features = [
  # the non-linking defaults laya needs, e.g. "std", "ndarray", "tracing" (whatever ort's defaults are minus download-binaries)
] }

[features]
default = ["download", "download-binaries"]
download-binaries = ["ort/download-binaries"]
load-dynamic = ["ort/load-dynamic"]
cuda = ["ort/cuda"]
directml = ["ort/directml"]
```

Nothing changes for existing users. A downstream crate can then use
`laya-onnx = { version = "...", default-features = false, features = ["load-dynamic"] }`.

With `load-dynamic`, the ONNX Runtime library location also needs to be settable. Either document
`ORT_DYLIB_PATH`, or add an optional `LayaOptions` field or helper that calls ort's
initialization with an explicit path before the first `Session` is built.

### Alternatives considered

- `[patch.crates-io]` with a fork carrying this change. That's what I'll do in the meantime, but a
  fork has to be rebased on every `laya-onnx` release.
- Vendoring a patched copy of `laya-onnx`. This has the same maintenance cost, and it's worse for
  provenance.
- `ORT_LIB_LOCATION` (link against a system ONNX Runtime at build time). This still requires
  ONNX Runtime on the build machine, which CRAN doesn't provide.

### Use case

An R package (`layaR`, via extendr) that builds offline on CRAN and on Windows/Rtools, and fetches
ONNX Runtime on first use. Any other language binding with offline or non-MSVC builds (conda-forge,
Debian packaging, Nix sandboxes) benefits too.

### Prior art

- ort's own `load-dynamic` feature and its documentation on alternative backends and linking.
- The CRAN `torch` package (runtime download of libtorch on first use).
- `laya-onnx`'s existing `cuda` and `directml` passthrough features, which this would follow.

---

## Not filed for now

- **U3 (serde on results and questions)**, **U4 (noul `labels`, hooks, histogram calibration)**
  and **U5 (token counting)** are nice-to-haves. layaR works around them. File them later if they
  become painful.
