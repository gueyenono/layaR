#' Built-in question presets
#'
#' Ready-made question sets ported from the Python SDK's presets. Each
#' preset's instructions refer to one field of the state, so pass the state
#' as a named list with that field (see `laya_preset_fields()`).
#'
#' | Preset | State field | Questions |
#' |---|---|---|
#' | `triage` | `message` | intent, is_urgent, frustration, refund_requested, churn_risk |
#' | `email` | `body` | category, is_spam, is_phishing, urgency, needs_reply |
#' | `guard` | `prompt` | jailbreak, prompt_injection, sensitive_data, harm_severity, topic |
#' | `moderation` | `post` | toxic, harassment, threat, spam, severity |
#' | `router` | `request` | difficulty, domain, needs_tools, is_sensitive |
#'
#' @param name The preset name.
#' @param categories For the `email` preset only: the routing categories, as
#'   a named character vector (`c(label = "description")`) in offer order.
#'   `NULL` uses the defaults (billing, technical, sales, security, hr, other).
#' @return A `laya_questions` object.
#' @examples
#' laya_preset("triage")
#' laya_preset("email", categories = c(orders = "order status, shipping",
#'                                     returns = "returns and exchanges"))
#' laya_preset_fields()
#' @export
laya_preset <- function(name = c("triage", "email", "guard", "moderation", "router"),
                        categories = NULL) {
  name <- match.arg(name)
  cats <- "null"
  if (!is.null(categories)) {
    if (is.null(names(categories)) || any(names(categories) == "")) {
      laya_abort("{.arg categories} must be named: {.code c(label = \"description\")}.",
                 kind = "invalid_argument")
    }
    check_unique(names(categories), "category")
    cats <- as.character(to_json(as.list(categories)))
  }
  json <- rs_unwrap(rs_preset(name, cats))
  as_laya_questions(from_json(json))
}

#' @rdname laya_preset
#' @export
laya_preset_fields <- function() {
  data.frame(
    preset = c("triage", "email", "guard", "moderation", "router"),
    state_field = c("message", "body", "prompt", "post", "request")
  )
}
