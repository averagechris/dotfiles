---
name: linear-cli
description: |
  Quick reference for using the local linear binary when the Linear MCP is missing features.
---

# Linear CLI

Use this skill when you need the local `linear` binary instead of, or in addition to, the Linear MCP.

## Rules

- Prefer non-interactive commands.
- Prefer machine-readable output when possible.
- Do not assume the Linear MCP can do everything; use `linear` for gaps.

## Good defaults

```bash
linear --help
linear whoami
linear i list --output json --compact
linear i get LIN-123 --output json --compact
linear p get PROJECT_ID --output json --compact
```

## Common commands

```bash
# Issues
linear i list --mine
linear i get LIN-123
linear i create "Title" -t ENG
linear i update LIN-123 -s Done
linear i comment LIN-123 -b "Comment"

# Projects / cycles / users
linear p get PROJECT_ID
linear cycles list -t ENG
linear users list
linear whoami

# Raw API escape hatch
linear api query '{ viewer { name email } }'
```

## Agent usage

- Prefer `--output json --compact` for automation.
- Use `--id-only` when you need a resource ID for chaining.
- Avoid interactive/TUI commands unless the user explicitly asks for them.
