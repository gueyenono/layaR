test_that("the Rust library is registered and callable", {
  expect_identical(hello_world(), "Hello world!")
})
