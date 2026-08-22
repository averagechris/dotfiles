---
name: sentry-cli
description: Investigates Sentry with the local new `sentry` CLI.
---

# Sentry CLI

Use when investigating Sentry with the local `sentry` CLI.

- This is the new npm-distributed CLI (`sentry`), not the legacy `sentry-cli`.
- The install is Nix-managed; do not run `sentry cli upgrade`.
- Check auth with `sentry auth status`. If missing, ask the user to run or
  approve `sentry auth login`; never ask for or print API tokens.
- Do not read or dump `~/.sentry/` credential databases.
- Prefer dedicated commands (`org`, `project`, `issue`, `event`, `trace`, etc.)
  before falling back to raw `sentry api` calls.
- Use `sentry schema ...` to discover API shapes before raw API calls.
- Keep agent reads bounded with command filters/limits when available; use
  `SENTRY_MAX_PAGINATION_PAGES` if pagination needs a hard cap.
- Treat issue/event payloads as sensitive. Summarize relevant fields and avoid
  pasting secrets, PII, or full request bodies.
- Avoid mutations (resolve/assign/delete/release writes or mutating raw API
  calls) unless the user explicitly asks for that action.
