# Built-in question presets

Ready-made question sets ported from the Python SDK's presets. Each
preset's instructions refer to one field of the state, so pass the state
as a named list with that field (see `laya_preset_fields()`).

## Usage

``` r
laya_preset(
  name = c("triage", "email", "guard", "moderation", "router"),
  categories = NULL
)

laya_preset_fields()
```

## Arguments

- name:

  The preset name.

- categories:

  For the `email` preset only: the routing categories, as a named
  character vector (`c(label = "description")`) in offer order. `NULL`
  uses the defaults (billing, technical, sales, security, hr, other).

## Value

A `laya_questions` object.

## Details

|  |  |  |
|----|----|----|
| Preset | State field | Questions |
| `triage` | `message` | intent, is_urgent, frustration, refund_requested, churn_risk |
| `email` | `body` | category, is_spam, is_phishing, urgency, needs_reply |
| `guard` | `prompt` | jailbreak, prompt_injection, sensitive_data, harm_severity, topic |
| `moderation` | `post` | toxic, harassment, threat, spam, severity |
| `router` | `request` | difficulty, domain, needs_tools, is_sensitive |

## Examples

``` r
laya_preset("triage")
#> <laya_questions> 5 questions
#>   intent            choice What does the customer want in `message`?  [6 options: refund, technical_help, billing_questio…]
#>   is_urgent         noul   Does `message` communicate time pressure or a deadline?  [yes/no]
#>   frustration       score  How frustrated does the customer sound in `message`?  [4 levels]
#>   refund_requested  noul   Does the customer ask for money back?  [yes/no]
#>   churn_risk        noul   Does `message` suggest the customer may leave for a competi…  [yes/no]
laya_preset("email", categories = c(orders = "order status, shipping",
                                    returns = "returns and exchanges"))
#> <laya_questions> 5 questions
#>   category     choice Which team should handle the email in `body`?  [2 options: orders, returns]
#>   is_spam      noul   Is this email unsolicited spam or bulk marketing?  [yes/no]
#>   is_phishing  noul   Is this email a phishing or scam attempt to steal money, cr…  [yes/no]
#>   urgency      score  How urgent is the request in `body`?  [3 levels]
#>   needs_reply  noul   Does the sender expect a reply?  [yes/no]
laya_preset_fields()
#>       preset state_field
#> 1     triage     message
#> 2      email        body
#> 3      guard      prompt
#> 4 moderation        post
#> 5     router     request
```
