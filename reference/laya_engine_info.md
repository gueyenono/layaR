# Inspect or close an engine

`laya_engine_info()` reports what an engine loaded: checkpoint, ONNX
layout, file paths, sequence budgets (`max_len`, `head_max_len`) and
calibration temperatures. `laya_engine_close()` frees the model's memory
right away instead of waiting for garbage collection; the engine can't
be used afterwards.

## Usage

``` r
laya_engine_info(engine)

laya_engine_close(engine)
```

## Arguments

- engine:

  A `laya_engine`.

## Value

`laya_engine_info()` returns a list; `laya_engine_close()` returns
`engine`, invisibly.

## Examples

``` r
if (laya_model_available()) {
  engine <- laya_engine()
  str(laya_engine_info(engine), max.level = 1)
  laya_engine_close(engine)
}
```
