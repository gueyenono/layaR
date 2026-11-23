# Data frames, batches and long documents

``` r

library(layaR)

questions <- laya_questions(
  department = laya_choice(
    "Which department should handle this request?",
    billing   = "invoices, payments, refunds",
    technical = "bugs, outages, system errors",
    sales     = "pricing, new contracts",
    other     = "everything else"
  ),
  urgency = laya_score("How urgent is this request?",
                       c("not urgent", "soon", "critical deadline or blocking issue")),
  churn_risk = laya_noul("Does the customer say they will cancel or leave?")
)

tickets <- data.frame(
  id = 1:6,
  subject = c("Duplicate charge", "App crashes on login", "Pricing for 50 seats",
              "Cancel my account", "Export to CSV?", "Server down!!!"),
  body = c(
    "We were billed twice for March. Refund it or we cancel.",
    "Since the last update the app closes as soon as I log in.",
    "We're a team of 50 and want a quote for the annual plan.",
    "Your service has been unreliable for months. Please close my account.",
    "Is there a way to export my reports to CSV?",
    "Production is down and our customers can't check out. Fix this now."
  )
)
```

The examples here use base R. For the same workflows written with dplyr,
tidyr and purrr, see [Using layaR with the
tidyverse](https://gueyenono.github.io/layaR/articles/tidyverse.html).

## Annotating a data frame

[`laya_annotate()`](https://gueyenono.github.io/layaR/dev/reference/laya_annotate.md)
asks the same questions about every row and adds the answers as columns.
`state` names the column or columns the model reads; with several, each
row becomes a structured state such as `{"subject": ..., "body": ...}`,
which keeps the field names as context.

``` r

annotated <- laya_annotate(tickets, questions, state = c("subject", "body"))
annotated[, -(2:3)]
#>   id department department_confidence urgency urgency_confidence churn_risk
#> 1  1    billing                1.0000  1.8407             0.5858     0.6004
#> 2  2  technical                0.9867  1.8314             0.5719     0.5041
#> 3  3      sales                0.9935  1.6067             0.3052     0.0227
#> 4  4  technical                0.7906  1.8426             0.5930     0.9880
#> 5  5  technical                0.7456  1.6526             0.3477     0.0034
#> 6  6  technical                0.8752  1.9345             0.7765     0.9800
#>   churn_risk_confidence
#> 1                0.6004
#> 2                0.5041
#> 3                0.9773
#> 4                0.9880
#> 5                0.9966
#> 6                0.9800
```

Each question adds a column of the natural type:

- a choice question gives a **factor** whose levels are the options, in
  order, so [`table()`](https://rdrr.io/r/base/table.html) and grouping
  work as you’d expect;
- a score question gives the expected level, a number;
- a yes/no question gives the probability that the statement is true.

Plus a `_confidence` column per question. So the usual data-frame tools
apply directly:

``` r

table(annotated$department)
#> 
#>   billing technical     sales     other 
#>         1         4         1         0
annotated |> subset(churn_risk > 0.5, select = c(id, subject, churn_risk))
#>   id              subject churn_risk
#> 1  1     Duplicate charge     0.6004
#> 2  2 App crashes on login     0.5041
#> 4  4    Cancel my account     0.9880
#> 6  6       Server down!!!     0.9800
```

Tickets 1 and 4 do talk about cancelling. The model also flags the angry
outage report (6), and the crash report (2) only just: an upset customer
is not the same as a leaving one. A threshold is a choice about which
mistakes you can live with; check it against labelled rows from your own
data.

`probabilities = TRUE` adds a list-column with each option’s
probability, `answer_confidence = TRUE` a column with the confidence in
each answer given (see below), `prefix` names the new columns
differently, and rows whose state columns are all `NA` get `NA` answers
without a prediction. A tibble stays a tibble.

### Abstaining on uncertain rows

With `min_confidence`, each answer also gets an `_abstained` column. The
answer is kept, so you choose what to do with the uncertain rows.

The gate compares the threshold with each answer’s `answer_confidence`,
which for a choice question is the probability of the chosen option.
That can differ from the `_confidence` column, a calibrated measure over
all the options. `answer_confidence = TRUE` shows what the gate sees:

``` r

gated <- laya_annotate(tickets, questions["department"], state = c("subject", "body"),
                       min_confidence = 0.99, answer_confidence = TRUE)
gated |>
  subset(select = c(id, department, department_answer_confidence, department_abstained))
#>   id department department_answer_confidence department_abstained
#> 1  1    billing                       1.0000                FALSE
#> 2  2  technical                       0.9976                FALSE
#> 3  3      sales                       0.9990                FALSE
#> 4  4  technical                       0.9387                 TRUE
#> 5  5  technical                       0.9200                 TRUE
#> 6  6  technical                       0.9634                 TRUE
```

## Batches

[`laya_predict_batch()`](https://gueyenono.github.io/layaR/dev/reference/laya_predict.md)
is the lower-level function behind
[`laya_annotate()`](https://gueyenono.github.io/layaR/dev/reference/laya_annotate.md):
it takes a character vector, a list of states or a data frame, and
returns a list of full results in input order.

``` r

batch <- laya_predict_batch(tickets[c("subject", "body")], questions)
batch
#> <laya_batch_result> 6 states · 3 questions · 1188 input tokens
#>   questions: department, urgency, churn_risk
#>   use as.data.frame() for one row per state and question
head(as.data.frame(batch), 6)
#>   state_id         id   type    answer  value confidence answer_confidence
#> 1        1 department choice   billing 1.0000     1.0000            1.0000
#> 2        1    urgency  score      1.84 1.8407     0.5858            0.8478
#> 3        1 churn_risk   noul      TRUE 0.6004     0.6004            0.6004
#> 4        2 department choice technical 0.9976     0.9867            0.9976
#> 5        2    urgency  score      1.83 1.8314     0.5719            0.8380
#> 6        2 churn_risk   noul      TRUE 0.5041     0.5041            0.5041
#>   act_probability abstention
#> 1               1       <NA>
#> 2               1       <NA>
#> 3               1       <NA>
#> 4               1       <NA>
#> 5               1       <NA>
#> 6               1       <NA>
```

[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) gives one
row per state and question, with a `state_id`;
[`laya_probabilities()`](https://gueyenono.github.io/layaR/dev/reference/laya_result.md)
gives one row per option.

States are sent to the engine in chunks of `chunk_size` (64 by default).
Between chunks R can be interrupted and the progress bar updates, so a
large batch can be stopped with Esc or Ctrl+C. `batch_size` (1 by
default) and `sort_by_length` control how a chunk is split into forward
passes. They change the speed, not the answers; see
[`vignette("models-and-performance", package = "layaR")`](https://gueyenono.github.io/layaR/dev/articles/models-and-performance.md).

## Long documents

A checkpoint reads a limited number of tokens. Longer text is truncated
by
[`laya_predict()`](https://gueyenono.github.io/layaR/dev/reference/laya_predict.md);
[`laya_predict_long()`](https://gueyenono.github.io/layaR/dev/reference/laya_predict.md)
instead scans it in overlapping windows and keeps, for each question,
the answer from the most confident window. The answer records which
window it came from.

``` r

contract <- paste(
  strrep("This agreement covers the provision of hosting services. ", 120),
  "Either party may terminate this agreement with 30 days written notice.",
  strrep("Fees are payable monthly in advance. ", 120)
)
clause <- laya_questions(
  termination = laya_noul("Does the text allow either party to terminate the agreement?")
)
res <- laya_predict_long(contract, clause)
res
#> <laya_result> laya-rl-agent · 1 answer · 3641 input tokens · 5 windows
#>   termination  noul    0.70 → TRUE   confidence 0.70
str(res$answers$termination$window)
#> List of 4
#>  $ index      : int 2
#>  $ token_start: int 760
#>  $ token_end  : int 1520
#>  $ count      : int 5
```

`window` and `stride` (in tokens) control the scan. By default the
window is the room the questions leave and the stride is half of it.

## Emails

[`laya_email_state()`](https://gueyenono.github.io/layaR/dev/reference/laya_email_state.md)
builds the state the Python SDK builds for an email: the subject, a
cleaned body and the sender. Cleaning removes quoted replies, signatures
and legal disclaimers so the model reads only the new message.

``` r

raw <- paste(
  "Hi, the invoice for March was charged twice. Can you refund one of them?",
  "",
  "Thanks,",
  "Ana",
  "--",
  "Ana Muller | Head of Finance | Acme Corp",
  "",
  "On Mon, 3 Mar 2025 at 10:00, Support <help@example.com> wrote:",
  "> Thanks for reaching out. How can we help?",
  sep = "\n"
)
email <- laya_email_state(subject = "Double charge", body = raw, sender = "ana@example.com")
str(email)
#> List of 3
#>  $ subject: chr "Double charge"
#>  $ body   : chr "Hi, the invoice for March was charged twice. Can you refund one of them?"
#>  $ from   : chr "ana@example.com"
laya_predict(email, laya_preset("email"))
#> <laya_result> laya-rl-agent · 5 answers · 409 input tokens
#>   category     choice  billing        p 1.00  confidence 1.00
#>   is_spam      noul    0.07 → FALSE  confidence 0.93
#>   is_phishing  noul    0.01 → FALSE  confidence 0.99
#>   urgency      score   1.92 (0–2)    confidence 0.74
#>   needs_reply  noul    0.10 → FALSE  confidence 0.90
```

[`laya_clean_email()`](https://gueyenono.github.io/layaR/dev/reference/laya_clean_email.md)
does the cleaning alone, on a whole vector of bodies.

## Languages

The `multilingual` checkpoint reads 100+ languages; the `english` one
only English.
[`laya_detect_language()`](https://gueyenono.github.io/layaR/dev/reference/laya_detect_language.md)
tells you which a text needs, without a model:

``` r

texts <- c(
  "Please refund the duplicate charge",
  "Me cobraron dos veces este mes. ¿Pueden devolverme el dinero?",
  "ฉันถูกเรียกเก็บเงินสองครั้ง"
)
laya_detect_language(texts) |> subset(select = c(script, language, is_english))
#>   script language is_english
#> 1  latin       en       TRUE
#> 2  latin       es      FALSE
#> 3   thai     <NA>      FALSE
```

The multilingual checkpoint answers the same questions in any of them:

``` r

laya_predict_batch(texts, questions["department"]) |>
  as.data.frame() |>
  subset(select = c(state_id, answer, confidence))
#>   state_id  answer confidence
#> 1        1 billing     0.5778
#> 2        2 billing     0.9995
#> 3        3 billing     0.0600
```
