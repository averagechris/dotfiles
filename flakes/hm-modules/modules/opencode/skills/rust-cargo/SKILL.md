---
name: rust-cargo
description: Use for cargo builds, checks, tests, or clippy, including quiet output, scoped rebuilds, and shared compiler caches.
---

# Rust builds

Use `cargo check -q`, `cargo build -q`, `cargo test -q`, and `cargo clippy -q`. Scope repeated checks with `-p <crate>` or a test filter. For many diagnostics, use `--message-format=short`; rerun the specific failure for full detail. Send large logs to a file and inspect the relevant lines.

Use the host's configured build parallelism. After a tool timeout, rerun with a longer timeout to reuse compiled artifacts. For suspect artifacts in one crate, use `cargo clean -p <crate>`.

## Compiler cache

`~/.cargo/config.toml` may set `rustc-wrapper = sccache`. Preserve that configuration. Setting `RUSTC_WRAPPER` to an empty value overrides it and disables the cache.

When an error specifically implicates sccache, retry once with `SCCACHE_DISABLE=1 cargo ...` and report the failure.
