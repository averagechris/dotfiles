# Agent Instructions for Dotfiles Repository

Keep this file minimal. Put durable topic guidance in `docs/`.

## Start Here

- Before changing a module, host, package, workflow, or user-facing behavior,
  read `docs/README.md` and the most relevant topic doc.
- If no relevant doc exists, create one or add durable notes to the closest
  existing doc.
- Repository tickets live in the SourceHut projects tracker under the
  `repo:dotfiles` label; see `docs/srht.md` for the issue workflow.

## Non-Negotiable Rules

- Never read `secrets/`, decrypted secret material, or files ending in `.age`
  without explicit permission.
- Keep documentation in sync with code. Any behavior, module, package, host,
  keybinding, command, or workflow change should update the corresponding doc and
  `docs/README.md` when the doc set changes.

## Repository Map

```text
flake.nix                         top-level aggregator flake
flakes/base-lib/                  shared library, overlays, packages, deploy helpers
flakes/nixos-modules/             reusable NixOS modules
flakes/hm-modules/                reusable Home Manager modules and OpenCode skills
flakes/darwin-modules/            reusable nix-darwin modules
flakes/hosts/<hostname>/          individual host flakes and configs
docs/                             canonical project documentation
secrets/                          encrypted agenix material; do not read casually
```

## Common Checks

Prefer these entry points; see the relevant docs for task-specific checks.

```bash
jj lint
nix flake check
nix flake check ./flakes/hosts/<hostname>
nh os build -q --no-nom . --hostname <hostname>
nh darwin build -q --no-nom . --hostname suremac
update-flakes --check
```

Use `nh` for NixOS/Darwin build/switch workflows when possible, `nom` for raw
Nix builds/develop shells, and `nix flake check` for flake checks.

## Where to Put Knowledge

- Add or update durable instructions in the most specific doc under `docs/`.
- Add new docs to `docs/README.md`.
- Keep agent-only operational shortcuts in repo-managed skills, not here.
- Update `AGENTS.md` only for repo-wide bootstrap rules, safety constraints, or
  documentation routing that every agent must see by default.

## High-Value References

- `docs/README.md` - documentation index.
- `docs/nixos.md` - general NixOS notes.
- `docs/manual-package-updates.md` - `update-flakes`, cooldowns, and fixed-hash
  package updates.
- `docs/opencode.md` and `docs/opencode-pr-review.md` - OpenCode module,
  permissions, skills, tools, and PR review workflow.
- `docs/jj-pr-workflow.md`, `docs/jj-workspaces.md`, and `docs/jj-tag-workflow.md`
  - jj helper workflows.
- `docs/trainwreck.md` - trainwreck VPS role and deployment notes.
- `docs/troubleshooting/` - troubleshooting guides.
