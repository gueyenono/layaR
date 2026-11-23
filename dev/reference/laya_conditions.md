# Laya conditions

Every error layaR raises has class `laya_error` plus a specific class
`laya_error_<kind>`, so you can handle one kind of failure on its own,
for example `tryCatch(..., laya_error_no_markers = function(e) ...)`.
The kind is also stored in the condition's `kind` field. Warnings from
the engine (for example a long-document window being capped) have class
`laya_warning`.

## Details

Kinds from the engine: `io`, `json`, `artifacts_not_found`,
`directory_not_found`, `missing_file`, `download`, `tokenizer`, `onnx`,
`invalid_question`, `invalid_config`, `checkpoint_mismatch`,
`no_markers`, `invalid_state`, `unsupported_aggregate`,
`invalid_window`, `not_supported`, `invalid_min_confidence`. Kinds from
layaR itself: `model_not_found`, `model_not_published`, `model_exists`,
`runtime_not_found`, `runtime_load`, `invalid_argument`, `forked`,
`bridge_json`, `bridge_invalid_option`, `bridge_engine_closed`,
`bridge_panic`. Model downloads and imports also use the engine's
`download`, `io` and `artifacts_not_found`.
