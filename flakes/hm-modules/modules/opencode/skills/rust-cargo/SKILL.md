---
name: rust-cargo
description: "Use when running cargo builds, checks, tests, or clippy in agent sessions: quiet output flags, scoping rebuilds, sccache/RUSTC_WRAPPER cache behavior, and diagnosing slow or hung builds. Do not use for writing or reviewing Rust code."
---

# Rust and cargo for agents

## Keep cargo output out of context

Cargo's progress stream (`Compiling dep v1.2.3` for every crate) is pure noise in agent context. Default to quiet invocations; warnings and errors still print in full.

```bash
cargo check -q
cargo build -q
cargo test -q
cargo clippy -q
```

- Triaging many diagnostics: add `--message-format=short` for one-line errors/warnings, then rerun the narrow case without it for the full rendered diagnostic.
- Scope rebuild loops to the crate you are editing: `cargo check -q -p <crate>`.
- Tests: `cargo test -q` quiets the build; add `-- --quiet` to compress per-test lines in large suites. Prefer the specific test or module over the whole suite.
- Never use `--message-format=json` for human-style inspection; it multiplies output size.
- Expected-large output (full suites, verbose builds): redirect to a file and inspect with `tail`/`rg` instead of streaming into context.

## Parallelism

Do not throttle builds with `-j`/`--jobs` on your own initiative. Dev machines are sized for full-parallel builds; `-j 2` can make a large workspace check take 5x longer and exceed tool timeouts. Limit jobs only when a repo's own instructions explicitly require it.

## When a build seems slow or hung

- Cold builds of large workspaces can legitimately exceed the default tool timeout. Progress persists in the target directory: rerun the same command with a larger `timeout`; it resumes where it stopped.
- A timeout is not evidence that the compiler wrapper or cache is broken. Do not change toolchain configuration to "fix" a slow build.
- Do not run `cargo clean` to fix weirdness; it destroys warm state. Prefer targeted `cargo clean -p <crate>` when a specific crate's artifacts are suspect.

## RUSTC_WRAPPER and compile caches

Check whether the host routes rustc through a shared compile cache:

```bash
rg rustc-wrapper ~/.cargo/config.toml
```

If it does, never clear it: `RUSTC_WRAPPER= cargo ...` and `env RUSTC_WRAPPER= cargo ...` give the empty variable precedence over `~/.cargo/config.toml`, silently disabling the cache for every crate compiled in that invocation. If a command fails with an error that specifically implicates the wrapper, retry once with `SCCACHE_DISABLE=1 cargo ...` and report the observed failure in your handoff instead of adopting the workaround as a habit.
