---
name: linear-cli
description: |
  Quick reference for using the local linear-cli when the Linear MCP is missing features.
---

# Linear CLI

Use this skill when you need the local `linear-cli` instead of, or in addition to, the Linear MCP.

## Rules

- Prefer non-interactive commands.
- Prefer machine-readable output when possible.
- Do not assume the Linear MCP can do everything; use `linear-cli` for gaps.

## Good defaults

```bash
linear-cli --help
linear-cli whoami
linear-cli i list --output json --compact
linear-cli i get LIN-123 --output json --compact
linear-cli p get PROJECT_ID --output json --compact
```

## Common commands

```bash
# Issues
linear-cli i list --mine
linear-cli i get LIN-123
linear-cli i create "Title" -t ENG
linear-cli i update LIN-123 -s Done
linear-cli i comment LIN-123 -b "Comment"

# Projects / cycles / users
linear-cli p get PROJECT_ID
linear-cli cycles list -t ENG
linear-cli users list
linear-cli whoami

# Raw API escape hatch
linear-cli api query '{ viewer { name email } }'
```

## Agent usage

- Prefer `--output json --compact` for automation.
- Use `--id-only` when you need a resource ID for chaining.
- Avoid interactive/TUI commands unless the user explicitly asks for them.
