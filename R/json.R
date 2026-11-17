# The one place R values become JSON for the bridge (plan section 8).
#
# Numbers follow Python's int/float split, because the engine re-serializes a
# structured state the way Python's json.dumps does and the model reads that
# text: an R integer is a JSON int (`3`), an R double always has a decimal
# point (`149.0`, like a Python float), and doubles keep 17 significant digits
# so they reach Rust bit-for-bit (Rust then prints Python's shortest repr).
# jsonlite's defaults (4 digits, or 15 with digits = NA, and `2` for 2.0)
# change the tokens the model sees.
#
# `empty_object = TRUE` writes an empty list as `{}` (options objects);
# `array = TRUE` keeps a list as a JSON array even when it has one element.
to_json <- function(x, empty_object = FALSE, array = FALSE) {
  if (empty_object && is.list(x) && !length(x)) return(structure("{}", class = "json"))
  if (array && is.list(x) && !length(x)) return(structure("[]", class = "json"))
  jsonlite::toJSON(
    x,
    auto_unbox = TRUE, digits = I(17), always_decimal = TRUE, null = "null", na = "null",
    POSIXt = "ISO8601", Date = "ISO8601", factor = "string"
  )
}

from_json <- function(x) {
  jsonlite::fromJSON(x, simplifyVector = FALSE)
}
