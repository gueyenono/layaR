# Remove an installed model

Deletes a checkpoint from layaR's model root, freeing about 1.3 GB. A
model imported as a symlink only loses the link. Models in the shared
cross-SDK cache are never touched.

## Usage

``` r
laya_remove_model(
  checkpoint = c("multilingual", "english", "typed-decisions"),
  ask = interactive()
)
```

## Arguments

- checkpoint:

  Which checkpoint to remove.

- ask:

  Ask for confirmation first? Defaults to `TRUE` in interactive
  sessions.

## Value

`TRUE` if a model was removed, invisibly.

## Examples

``` r
if (FALSE) { # \dontrun{
laya_remove_model("english")
} # }
```
