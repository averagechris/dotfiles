---
name: rust-cargo
description: Cargo/Rust build hygiene for agents - concise output flags to keep
  build noise out of context, correct sccache/RUSTC_WRAPPER behavior, and what
  to do when a build seems slow or hung.
---

# Rust / Cargo for agents

## Keep cargo output out of context

Cargo's progress stream (`Compiling dep v1.2.3` for every crate) is pure noise
in agent context. Default to quiet invocations; warnings and errors still
print in full.

```bash
cargo check -q
cargo build -q
cargo test -q
cargo clippy -q
```

- Triaging many diagnostics: add `--message-format=short` for one-line
  errors/warnings, then re-run the narrow case without it if you need the full
  rendered diagnostic.
- Scope rebuild loops to the crate you are editing: `cargo check -q -p <crate>`.
- Test runs: `cargo test -q` already quiets the build; add `-- --quiet` to
  compress per-test lines when a suite is large. Prefer running the specific
  test or module you are working on over the whole suite.
- Never use `--message-format=json` for human-style inspection; it multiplies
  output size.
- Expected-large output (full test suites, verbose builds): redirect to a file
  and inspect with `tail`/`rg` rather than letting it stream into context.

## Parallelism

Do not throttle builds with `-j`/`--jobs` on your own initiative. Dev machines
are sized for full-parallel builds; `-j 2` can make a large workspace check
take 5x longer and then exceed tool timeouts. Only limit jobs when a repo's
own instructions explicitly require it.

## When a build seems slow or hung

- Cold builds of large workspaces can legitimately exceed the default tool
  timeout. Progress persists in the target directory: simply re-run the same
  command with a larger `timeout`; it resumes where it stopped.
- A timeout is not evidence that the compiler wrapper or cache is broken. Do
  not start changing toolchain configuration to "fix" a slow build.
- Do not run `cargo clean` to fix weirdness; it destroys warm state. Prefer
  targeted `cargo clean -p <crate>` if a specific crate's artifacts are
  suspect.

## RUSTC_WRAPPER and compile caches

Check whether the host routes rustc through a shared compile cache:

```bash
rg rustc-wrapper ~/.cargo/config.toml
```

If it does, never clear it: `RUSTC_WRAPPER= cargo ...` and
`env RUSTC_WRAPPER= cargo ...` give the empty variable precedence over
`~/.cargo/config.toml`, silently disabling the cache for every crate compiled
in that invocation. If a command fails with an error that specifically
implicates the wrapper, retry once with `SCCACHE_DISABLE=1 cargo ...` and
report the observed failure in your handoff instead of adopting the
workaround as a habit.
