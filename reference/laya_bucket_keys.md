# Bucket names for `min_confidence`

A per-bucket `min_confidence` gives a threshold per question type and
option count. These are the valid names; `"default"` also applies to
every bucket not named.

## Usage

``` r
laya_bucket_keys()
```

## Value

A character vector.

## Examples

``` r
laya_bucket_keys()
#>  [1] "choice:2"    "choice:3-5"  "choice:6-10" "choice:11+"  "score:2"    
#>  [6] "score:3-5"   "score:6-10"  "score:11+"   "noul:2"      "noul:3-5"   
#> [11] "noul:6-10"   "noul:11+"   
```
