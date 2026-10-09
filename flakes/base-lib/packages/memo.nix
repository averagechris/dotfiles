{package}:
package.overrideAttrs (_: {
  # Rust's test harness can fork while an integration test copies the memo
  # executable; inherited write descriptors can make the copy temporarily
  # unexecutable with ETXTBSY. Keep the checks enabled and serialize them.
  RUST_TEST_THREADS = "1";
})
