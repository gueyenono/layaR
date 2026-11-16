# The one place R values become JSON for the bridge (plan section 8).
# digits = NA is mandatory: jsonlite's default of 4 digits would silently
# change states and thresholds.
#
# `empty_object = TRUE` writes an empty list as `{}` (options objects);
# `array = TRUE` keeps a list as a JSON array even when it has one element.
to_json <- function(x, empty_object = FALSE, array = FALSE) {
  if (empty_object && is.list(x) && !length(x)) return(structure("{}", class = "json"))
  if (array && is.list(x) && !length(x)) return(structure("[]", class = "json"))
  jsonlite::toJSON(
    x,
    auto_unbox = TRUE, digits = NA, null = "null", na = "null",
    POSIXt = "ISO8601", Date = "ISO8601", factor = "string"
  )
}

from_json <- function(x) {
  jsonlite::fromJSON(x, simplifyVector = FALSE)
}
