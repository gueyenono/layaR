# The one place R values become JSON for the bridge (plan section 8).
# digits = NA is mandatory: jsonlite's default of 4 digits would silently
# change states and thresholds.
to_json <- function(x) {
  jsonlite::toJSON(
    x,
    auto_unbox = TRUE, digits = NA, null = "null", na = "null",
    POSIXt = "ISO8601", Date = "ISO8601", factor = "string"
  )
}

from_json <- function(x) {
  jsonlite::fromJSON(x, simplifyVector = FALSE)
}
