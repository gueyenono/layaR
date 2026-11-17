# Package index

## Questions

Build typed questions, or use a ready-made set.

- [`laya_choice()`](https://gueyenono.github.io/layaR/reference/laya_question.md)
  [`laya_score()`](https://gueyenono.github.io/layaR/reference/laya_question.md)
  [`laya_noul()`](https://gueyenono.github.io/layaR/reference/laya_question.md)
  : Build Laya questions
- [`laya_questions()`](https://gueyenono.github.io/layaR/reference/laya_questions.md)
  : Combine questions into a question set
- [`laya_preset()`](https://gueyenono.github.io/layaR/reference/laya_preset.md)
  [`laya_preset_fields()`](https://gueyenono.github.io/layaR/reference/laya_preset.md)
  : Built-in question presets
- [`as_laya_questions()`](https://gueyenono.github.io/layaR/reference/as_laya_questions.md)
  : Convert to a question set
- [`laya_validate_questions()`](https://gueyenono.github.io/layaR/reference/laya_validate_questions.md)
  : Validate a question set without a model
- [`laya_questions_to_json()`](https://gueyenono.github.io/layaR/reference/laya_questions_to_json.md)
  : Write a question set as JSON

## Predicting

- [`laya_predict()`](https://gueyenono.github.io/layaR/reference/laya_predict.md)
  [`laya_predict_batch()`](https://gueyenono.github.io/layaR/reference/laya_predict.md)
  [`laya_predict_long()`](https://gueyenono.github.io/layaR/reference/laya_predict.md)
  [`predict(`*`<laya_engine>`*`)`](https://gueyenono.github.io/layaR/reference/laya_predict.md)
  : Answer typed questions about a state

- [`laya_annotate()`](https://gueyenono.github.io/layaR/reference/laya_annotate.md)
  : Annotate a data frame

- [`laya_bucket_keys()`](https://gueyenono.github.io/layaR/reference/laya_bucket_keys.md)
  :

  Bucket names for `min_confidence`

## Results

- [`as.data.frame(`*`<laya_result>`*`)`](https://gueyenono.github.io/layaR/reference/laya_result.md)
  [`laya_probabilities()`](https://gueyenono.github.io/layaR/reference/laya_result.md)
  [`laya_answer()`](https://gueyenono.github.io/layaR/reference/laya_result.md)
  [`as.data.frame(`*`<laya_batch_result>`*`)`](https://gueyenono.github.io/layaR/reference/laya_result.md)
  : Laya results

## Engines

A loaded checkpoint. The prediction functions use a default engine.

- [`laya_engine()`](https://gueyenono.github.io/layaR/reference/laya_engine.md)
  : Load a Laya engine
- [`laya_default_engine()`](https://gueyenono.github.io/layaR/reference/laya_default_engine.md)
  : Use the default engine
- [`laya_engine_info()`](https://gueyenono.github.io/layaR/reference/laya_engine_info.md)
  [`laya_engine_close()`](https://gueyenono.github.io/layaR/reference/laya_engine_info.md)
  : Inspect or close an engine

## Models

Download, import and list exported checkpoints.

- [`laya_models()`](https://gueyenono.github.io/layaR/reference/laya_models.md)
  : List checkpoints and whether they are installed
- [`laya_download_model()`](https://gueyenono.github.io/layaR/reference/laya_download_model.md)
  : Download a model
- [`laya_import_model()`](https://gueyenono.github.io/layaR/reference/laya_import_model.md)
  : Import an exported model
- [`laya_remove_model()`](https://gueyenono.github.io/layaR/reference/laya_remove_model.md)
  : Remove an installed model
- [`laya_model_root()`](https://gueyenono.github.io/layaR/reference/laya_model_root.md)
  [`laya_model_path()`](https://gueyenono.github.io/layaR/reference/laya_model_root.md)
  [`laya_model_available()`](https://gueyenono.github.io/layaR/reference/laya_model_root.md)
  : Where models live

## Text utilities

Language detection and email cleaning; no model needed.

- [`laya_detect_language()`](https://gueyenono.github.io/layaR/reference/laya_detect_language.md)
  : Detect the language of states
- [`laya_clean_email()`](https://gueyenono.github.io/layaR/reference/laya_clean_email.md)
  : Clean email bodies
- [`laya_email_state()`](https://gueyenono.github.io/layaR/reference/laya_email_state.md)
  : Build an email state

## Errors and options

- [`laya_conditions`](https://gueyenono.github.io/layaR/reference/laya_conditions.md)
  : Laya conditions
- [`layaR`](https://gueyenono.github.io/layaR/reference/layaR-package.md)
  [`layaR-package`](https://gueyenono.github.io/layaR/reference/layaR-package.md)
  : layaR: Local Laya Decision Models via Rust
