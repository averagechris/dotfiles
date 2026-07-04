# Agent Instructions for Dotfiles Repository

> **IMPORTANT**: When working with this repository, load the `nix-dotfiles` skill:
> ```
> /load-skill nix-dotfiles
> ```
> This provides context about repo structure, build commands, and patterns.

## Repository Overview

This is a multi-flake Nix repository managing NixOS and Darwin (macOS) system configurations. The architecture uses independent flakes for each host, with shared module flakes for reusability.

## Repository Structure

```
dotfiles/
├── flake.nix                    # Top-level aggregator flake
├── flakes/
│   ├── base-lib/                # Shared library (mkHost, mkDeploy, SSH keys, overlays)
│   ├── nixos-modules/           # Shared NixOS modules
│   ├── hm-modules/              # Shared home-manager modules  
│   ├── darwin-modules/          # Shared Darwin modules
│   └── hosts/                   # Individual host flakes
│       ├── suremac/             # Darwin (macOS) host
│       ├── trap/                # NixOS host
│       ├── thorny/              # NixOS host
│       ├── tom/                 # NixOS host (home-assistant)
│       ├── cruber/              # NixOS host
│       ├── tater/               # NixOS host (ThinkPad T14s)
│       ├── trainwreck/          # NixOS host (Hetzner VPS)
│       ├── taz/                 # NixOS host (inactive)
│       └── tootsie/             # NixOS host (inactive)
├── hm_modules/                  # Legacy (modules now in flakes/hm-modules/)
├── secrets/                     # Encrypted secrets (agenix)
├── scripts/                     # Utility scripts
├── docs/                        # Documentation (see docs/README.md)
└── .opencode/                   # OpenCode skills and config
```

## Build/Lint/Test Commands

```bash
# Run all configured lints (alejandra, statix, shellcheck)
jj lint

# Format quietly (use -qq to suppress error details too)
alejandra -q .

# Lint
statix check

# Test (top-level)
nix flake check

# Test (individual host)
nix flake check ./flakes/hosts/<hostname>

# Routine flake and manifest-enrolled manual package updates with supply-chain cooldowns
update-flakes --check
update-flakes

# Build NixOS host (preferred ergonomic wrapper)
nh os build . --hostname <hostname>
nh os build ./flakes/hosts/<hostname> --hostname <hostname>

# Build Darwin host (preferred ergonomic wrapper)
nh darwin build . --hostname suremac
nh darwin build ./flakes/hosts/suremac --hostname suremac

# Deploy NixOS hosts (via deploy-rs)
nix run .#deploy -- .#<hostname>

# Deploy Darwin host (manual - deploy-rs doesn't support Darwin)
nh darwin switch . --hostname suremac
```

Prefer `nh` for NixOS/Darwin build, test, and switch workflows. Use `nom` for raw
Nix build/develop commands (`nom build`, `nom develop`) so output is easier
to scan, but use `nix flake check` for flake checks because this `nom` wrapper
does not support `nom flake check`. In noninteractive agent/tool contexts, add `--no-nom` to `nh` builds or
switches (for example, `nh os build -q --no-nom . --hostname tater`) to avoid the
clock/progress animation and most store-path chatter flooding captured logs. Fall back to `nix`,
`nixos-rebuild`, or `darwin-rebuild` only when `nh`/`nom` cannot express the
operation or when a user explicitly asks for the lower-level command.

Use `update-flakes` from the dev shell (or `nix run .#update-flakes -- ...`) for
routine dependency updates. The implementation is the Rust `update-flakes`
package, exposed in the dev shell and as the top-level `.#update-flakes` app/package. It
updates flake inputs plus manifest-enrolled fixed-hash packages from
`manual-package-updates.json` unless `--no-manual-packages` is passed.
The manifest makes package enrollment data-driven; set `enabled = false` in the
manifest to persistently unenroll a package, or use `--skip-manual-package` /
`--manual-package` for one-off runs. It applies a default 7-day cooldown to
gated inputs and manual packages such as `pi` / `pi-coding-agent` so fresh
upstream releases are not pulled immediately. Override only after manual review
with `--ignore-cooldown`, or tune with `--cooldown-days`, `--cooldown-inputs`,
`FLAKE_UPDATE_COOLDOWN_DAYS`, `FLAKE_UPDATE_COOLDOWN_INPUTS`, and per-package
`cooldownDays` in `manual-package-updates.json`. GitHub-release manual packages
select the newest non-prerelease release older than the cooldown window rather
than skipping just because the absolute latest release is too fresh. By default,
`update-flakes` hides noisy `nix flake update` output; pass `--show-output` only
when raw Nix logs are needed for debugging.

When asked to bump a specific flake input manually, update every relevant
`flake.lock`, not just the lockfile in the flake that declares the input. This
multi-flake repo has nested host/module locks plus the top-level aggregator
lock, and commands such as `nh darwin switch .#suremac` use the root
`flake.lock`. For example, bumping suremac's `granola-cli` input requires
updating `flakes/hosts/suremac/flake.lock` (`nix flake update granola-cli` from
that host flake) and the root lock's nested `suremac/granola-cli` node
(`nix flake update suremac/granola-cli` from the repo root). Verify from the
same flake path the user will build or switch, not only from the nested flake.

Pi is currently packaged from pinned upstream release archives rather than a
flake input. Keep it that way unless there is a concrete need to consume Pi
source directly, apply local patches, or track a fork. Update Pi only after a
cooldown/review window; use the manifest-driven `update-flakes` manual package
phase to refresh all platform hashes together. See `docs/pi.md` and
`docs/manual-package-updates.md` for the update checklist and the tradeoffs of
not making it a flake input.

## Documentation

See [docs/README.md](/docs/README.md) for documentation index, including:
- [nixos.md](/docs/nixos.md) - General NixOS configuration notes
- [gander.md](/docs/gander.md) - Gander jj review TUI module, package input, and Colemak keybindings
- [gpg-signing.md](/docs/gpg-signing.md) - GPG signing setup for git and jj commits with agenix
- [opencode-pr-review.md](/docs/opencode-pr-review.md) - OpenCode PR review workflow, artifact tools, and posting flow
- [coderabbit-cli.md](/docs/coderabbit-cli.md) - CodeRabbit CLI package, suremac agent integration, and local review workflow

See `docs/troubleshooting/` for common issues and solutions.

## Code Style Guidelines

- Format with Alejandra (Nix formatter)
- Lint with Statix (disabled rules: empty_pattern, repeated_keys)
- Use attribute sets with named parameters
- Follow existing patterns for similar functionality
- Use `mk` prefix for library functions (mkHost, mkDeploy)
- Use `dotfiles.feature.enable = true/false` pattern for options
- Helper `mkDefaultEnabledOption` for boolean options
- Configure `permittedInsecurePackages` in individual host flakes (e.g., tom needs openssl-1.1.1w)

## Documentation Requirements

**All changes must include documentation updates, and all documentation must be accurate to the current code.**

### When Making Changes

1. **Update relevant documentation** - If you modify a module, update its corresponding doc file
2. **Update the docs index** - Add new documentation to `docs/README.md`
3. **Update `AGENTS.md`** - If adding new conventions, modules, or workflows
4. **Keep docs in sync** - Documentation should always reflect the current state

### Documentation Structure

- Module docs: `docs/<module-name>.md` (e.g., `docs/hyprland.md`)
- Index: `docs/README.md` - must list all docs with brief descriptions
- Troubleshooting: `docs/troubleshooting/<issue>.md`
- Agent instructions: `AGENTS.md` (this file)

### Keybinding/Config Documentation

For modules with keybindings or user-facing configuration:
- List all keybindings in table format
- Document submaps/modal modes with their key sequences
- Include "how to use" examples
- Keep keybinding docs in sync with the actual code

## Pre-Push Lints

The `jj push` alias automatically runs lints before pushing. Lints are configured via `.jj-lint.toml` in the repo root (VCS-tracked):

```toml
# .jj-lint.toml
lints = [
  { name = "alejandra", command = "alejandra --check ." },
  { name = "statix", command = "statix check" },
  "fd -e sh -e bash -e zsh -x shellcheck"
]
```

Lint entries may be strings or inline tables with `name` and `command`; omit
`name` to use the inferred display label.

Alternatively, you can configure lints in the local repo config (not VCS-tracked):

```toml
# .jj/repo/config.toml
[dotfiles]
push-lints = ["alejandra --check .", "statix check"]
```

- `jj lint` - run lints without pushing
- `jj lint onboard --print` - discover numbered candidate lint/test commands when no `jj lint` config exists; inspect Makefile/justfile/Python pyproject/tox/nox/Docker Compose/docs/CI/pre-commit hooks and prefer all-files aggregate commands
- `jj lint onboard --preview --select=1,3` - preview the `.jj-lint.toml` that would be generated for selected numbered suggestions
- `jj lint onboard --write --select=1,3` / `jj lint onboard --local --select=1,3` - persist only selected onboarding suggestions to tracked `.jj-lint.toml` or per-repo `dotfiles.push-lints`
- `jj push` - run lints, then push if they pass
- `jj ship` - finish and push current work; runs `jj lint` before moving bookmarks, ships the parent of the working copy so an already-empty `@` (for example after `jj new`) does not get pushed to `main`, refuses empty targets, and requires `--bookmark` instead of silently falling back to integration bookmarks; use `--tag vX.Y.Z` only for human/agent-created release tags
- `jj tag-push vX.Y.Z --revision <rev>` - publish an already-created human/agent release tag; do not expect `jj git push --all` to create new remote tags
- `jj sync` - fetch, prefer a remote integration bookmark, infer one base from `develop`/`dev`, then `main`/`master`/`trunk`, then `release*`, then `trunk()`, and rebase the current branch/stack onto that base; agents should prefer `jj sync -q --fail-on-conflicts` or `jj sync --json --fail-on-conflicts` when structured output is needed
- `jj sync --onto main` - override the inferred sync base explicitly (works with any revset)
- `jj pr` - suremac-only opt-in PR helper for GitHub work repos in jj workspaces; use `jj pr doctor` first, then `jj pr create --base <branch> --sync --run-lints --run-cr --ticket <ticket> --title <title> --body-file <file>` instead of bare `gh pr create`. Use `jj pr watch` for compact CI/review polling instead of dumping raw logs into agent context. The helper infers the GitHub repo from jj remotes and always passes `gh --repo`, so it works in non-colocated jj workspaces. When `--run-cr` is used, the helper passes CodeRabbit an explicit Git remote base derived from the resolved jj base (for example `main@origin` -> `origin/main`) to avoid stale local integration bookmarks ballooning reviews. See `docs/jj-pr-workflow.md`.
- `jj ws add <name> [-r <revset>] [-q]` - create a managed workspace at `<project-group>/<workspace-dir>/<repo-name>/<workspace-name>`; from a main checkout it bases on an inferred remote integration bookmark, and from another managed workspace it defaults to `@`
- `jj ws list`, `jj ws path <name>`, `jj ws forget <name>`, `jj ws prune` - list, locate, safely forget/delete, and prune managed workspace directories; avoid `--pick` in agent/noninteractive contexts
- `jj ws` - print concise workspace workflow usage
- `jj git push` - push directly, skip lints

`jj lint`, `jj ship`, `jj tag-push`, `jj sync`, `jj pr`, and `jj ws` are implemented by the embedded `jj-workflow` Rust helper in `flakes/hm-modules/modules/jujutsu/jj-workflow/` because the lint/onboarding, branch/remote, tag publishing, PR, and workspace resolution logic outgrew shell aliases. `jj push` delegates lint execution to the same helper before pushing. `jj sync` can use per-repo jj config `dotfiles.sync.remote` when multiple remote integration bookmarks exist. `jj pr` can use per-repo jj config `dotfiles.pr.auto-bookmark` and `dotfiles.pr.bookmark-template`; the global defaults are installed only when `dotfiles.jujutsu.prWorkflow.enable` is true. After `jj ship` lints pass, it pushes with `jj git push` to avoid duplicate lint runs.

Managed jj workspaces use `~/projects/ws/<repo>/<workspace>` on personal hosts. On `suremac`, both `~/projects/ws/<repo>/<workspace>` and `~/sureapp/ws/<repo>/<workspace>` are configured. `jj ws add` copies `.jj-lint.toml` into the new workspace when the destination does not already have one, including ignored/untracked local lint configs. If it copies an untracked `.envrc`, it also runs `direnv allow`; it also copies an untracked `.venv` with usable `.venv/bin/python` by default, attempting APFS/reflink clone first and repairing common virtualenv path references so dependency updates stay isolated to the workspace. Broken source virtualenvs are skipped rather than copied. Use `--venv=link` to share the source checkout's environment, or `--no-envrc`, `--no-venv`, and `--no-direnv` when local environment setup is undesirable. `jj ws forget` refuses unpublished work unless `--force`; it checks for any non-empty commit in the workspace stack that is not reachable from remote bookmarks or remote tags, so an empty `@` is safe only if its non-empty ancestors were pushed. It runs `docker compose down --remove-orphans --volumes` when compose files are detected so workspace smoke-test data is cleaned up; use `--keep-docker-volumes` to preserve Compose data intentionally. Use `jj ws forget <name> --dry-run` before cleanup when safety is unclear.

## Naming Conventions

- **Host flakes**: `flakes/hosts/<hostname>/` - one directory per host
- **Host configs**: `flakes/hosts/<hostname>/configuration.nix`
- **Hardware configs**: `flakes/hosts/<hostname>/hardware.nix`
- **NixOS modules**: `flakes/nixos-modules/modules/`
- **Home-manager modules**: `flakes/hm-modules/modules/` and `hm_modules/`
- **Darwin modules**: `flakes/darwin-modules/modules/`
- **Library functions**: `flakes/base-lib/lib/`

## Module Placement

| Type | Location | Use for |
|------|----------|---------|
| nixos-modules | `flakes/nixos-modules/modules/` | System services, daemons, NixOS-specific config |
| hm-modules | `flakes/hm-modules/modules/` | User dotfiles, CLI tools, per-user GUI apps |
| darwin-modules | `flakes/darwin-modules/modules/` | macOS-specific (skhd, karabiner, Homebrew) |

## Adding a New Host

1. Create directory: `flakes/hosts/<hostname>/`
2. Create files: `flake.nix`, `configuration.nix`, `hardware.nix` (NixOS only)
3. Use existing host as template (trap for NixOS, suremac for Darwin)
4. Add inputs: base-lib, nixos-modules (or darwin-modules), hm-modules
5. Update top-level `flake.nix` to import the new host
6. Test with `nix flake check ./flakes/hosts/<hostname>`

## Security Best Practices

- Only permit insecure packages where absolutely necessary
- Scope insecure package permissions to specific host flakes
- Add comments explaining why insecure packages are needed
- Never read files under `secrets/` or files ending with `.age` without explicit permission

## Keybinding Philosophy

- Use leader key (shift+space) to activate modal context
- Second key selects mode category (t=tab, w=window)
- Modes auto-exit after actions (except resize/continuous modes)
- Use Colemak Mod-DH navigation keys (mnei) instead of arrow keys
- Always provide explicit Escape key to exit any mode

## Agent VCS and Git Usage Reminder

- Agents MUST NOT run any git commands unless the user explicitly requests git operations
- The repository is managed with the `jj` VCS (colocated); use `jj` or follow user instructions for VCS actions
- If unsure, ask the user before performing any version-control operations

### jj-VCS Skill Sync

**Important**: If you modify any jj configuration in this repository (e.g., `.jj-lint.toml`, `.jj/repo/config.toml`, aliases, lint commands, or workspace behavior), you **must** update the relevant repo-managed jj skill. Shared skills are defined in `flakes/hm-modules/modules/opencode/skills.nix`; host-specific skills, such as `suremac-jj-pr`, may be wired directly from that host's configuration. Both are deployed via home-manager to `~/.config/opencode/skills/`.

- `jj-vcs` - short router when unsure which jj skill applies
- `jj-change-management` - everyday status/diff/log/describe/split/squash/rebase/bookmark workflow
- `jj-conflict-resolution` - conflict inspection, safe resolution, and recovery workflow
- `jj-repo-workflow` - `jj lint`, `jj sync`, `jj push`, `jj ship`, `jj tag-push`
- `suremac-jj-pr` - suremac-only OpenCode skill for `jj pr` GitHub PR creation/update/close/watch from jj workspaces
- `jj-workspaces` - `jj ws` workspace creation, path lookup, ticket workspaces, cleanup

## OpenCode PR Review Workflow

The `/review-pr` command and `github-pr-review` / `changes-review-core` skills are repo-managed in `flakes/hm-modules/modules/opencode/`. The artifact helpers (`review-artifact-generate`, `review-artifact-write`, `review-artifact-render`, and `review-github-post`) are OpenCode tools, not shell executables. Do not probe them with `type` or `command -v`; call them as tools. The module materializes a writable `~/.config/opencode/tools` copy, points `programs.opencode.tools` at that config-directory copy rather than the `/nix/store` source path, and declares `@opencode-ai/plugin` in `~/.config/opencode/package.json` so OpenCode can populate `node_modules` before importing custom tools. On Linux the module wraps OpenCode with `stdenv.cc.cc.lib` in `LD_LIBRARY_PATH` so native file-watcher bindings can find `libstdc++.so.6` when loading project files. PR reviews must fetch and use PR explainer links when present, include a compact walkthrough of the changes before comment triage, run an adversarial pressure-test of assumptions/alternatives/tradeoffs, then walk each candidate comment through approve/refine/change placement/drop/hold decisions before posting. In jj-managed repositories, the review flow must prefer `jj` for workspace/status/log/show/diff operations and avoid git checkout/status/diff commands unless the user explicitly requests git or no practical jj/gh alternative exists.

OpenCode is sourced from the upstream `github:anomalyco/opencode` flake input rather than nixpkgs so the installed CLI tracks upstream's frequent releases more closely. The shared base-lib overlay exposes that input as `pkgs.opencode`, and the hm-modules flake mirrors the overlay for standalone evaluation. OpenCode bash permissions match the extracted command source, not just the executable name. Inline environment assignments can therefore prevent a rule like `"just *": "allow"` from matching. The OpenCode module patches the upstream flake package's bash tool to strip safe leading inline environment assignments before permission matching, while preserving assignments with command substitutions so they still prompt. Prefer maintaining that patch over broad patterns like `*=* just *` because OpenCode wildcards are simple anchored globs and can match unrelated command arguments. If upstream OpenCode's `package.json` Bun requirement gets ahead of nixpkgs' `bun` package, keep any temporary Bun-version guard relaxation in the module patch set narrowly scoped to the current Bun minor series and remove it once nixpkgs catches up.

The OpenCode Build agent bash policy is open-by-default (`"*": "allow"`) with later `ask`/`deny` overrides for known sharp edges. The `orchestrator` primary agent shares that safety posture but is prompted to decompose ambitious projects, delegate self-contained coding tracks to `coding-minion`, and tell minions to use isolated `jj ws add <name> -q` workspaces with `jj ws forget <name>` cleanup once work is integrated or abandoned. The `coding-minion` subagent mirrors the Build agent's prompt, tools, steps, and permissions but defaults to `openrouter/openai/gpt-5.5` with the low variant for cheaper, faster routine coding delegation; keep its permission block synchronized with Build when changing Build permissions. Permission objects are last-match-wins, so keep the broad allow first and put risky patterns after it. Prompt-gated families include encrypted secret reads / `.env*`, remote login/copy, deploy/switch commands, broad or sensitive deletion targets, ownership/permission/disk commands, process/service control, VCS publication/history rewrites, GitHub admin surfaces, and Kubernetes mutating/session/secret commands. Privilege escalation commands (`sudo`, `doas`, `su`) are denied because agents cannot satisfy the password prompt anyway. Writing encrypted secret files and ordinary temp-file cleanup with `rm` should stay allowed unless a more specific risky pattern applies. When adding narrow allow rules in stricter agents, use an exact command plus a command-space wildcard (for example, `"rodney": "allow"` and `"rodney *": "allow"`) instead of a prefix wildcard like `"rodney*": "allow"`; prefix wildcards also allow unrelated executable names such as `rodney_malicious`. Conservative `ask`/`deny` override rules can be broader when the intent is to interrupt anything in that command family.

CodeRabbit CLI is packaged as `pkgs.coderabbit-cli` from the official Darwin binary archive and installed/exposed to OpenCode agents on `suremac` only (`cr`/`coderabbit`). Do not use `cr update` for this Nix-managed install; update it through `update-flakes --manual-packages-only --manual-package coderabbit-cli --manual-version coderabbit-cli=<version>` so the package version and hashes in `flakes/base-lib/packages/coderabbit-cli.nix` change together. The repo-managed `coderabbit-cli` OpenCode skill is configured for `suremac` only.

Datadog Pup CLI is packaged as `pkgs.pup` from official release archives and installed/exposed to OpenCode agents on `suremac` only (`pup`). The repo-managed `pup-cli` OpenCode skill is configured for `suremac` only; keep its public content concise and focused on low-token CLI patterns such as `--read-only`, `--no-agent`, `--jq`, bounded time windows/limits, and compact CSV/JSON output. Org-specific stack/ecosystem hints shared by Datadog, Sentry, and Kubernetes workflows are secret because this repo is public: store them in `secrets/opencode-sure-stack-context.age`, not in plaintext docs or skill files. `suremac` appends that decrypted secret to the local `sure-stack-context` skill during Home Manager activation.

Ctx is packaged from the SourceHut `ctx` flake input and exposed to OpenCode agents on `suremac` as `ctx` through `dotfiles.opencode.agentTools`, so primary agent runtime notes advertise local coding-agent history search. It is also installed on `tater`; update both host/root lock nodes when bumping the input.

`kubectl` is installed/exposed to OpenCode agents on `suremac` only (`kubectl`) for Kubernetes investigation alongside `pup` and `sentry`. The Build agent open bash default permits read-oriented kubectl investigation, while explicit overrides keep secret reads/describes plus mutating/session commands prompt-gated; prefer subcommand-first forms like `kubectl get pods -n namespace` so risky subcommand overrides still match without broad flag-prefixed patterns. The repo-managed `sure-stack-context` OpenCode skill is configured for `suremac` only and should route deployed-environment debugging across Datadog, Sentry, and Kubernetes while keeping public guidance generic and private company context in the encrypted appendix.

The new Sentry CLI is packaged as `pkgs.sentry` from the npm `sentry` tarball and installed/exposed to OpenCode agents on `suremac` only (`sentry`). This is distinct from nixpkgs' legacy `sentry-cli`; the command is `sentry` and requires Node.js 22.15+. The wrapper disables update checks because updates are Nix-managed; do not run `sentry cli upgrade`. The repo-managed `sentry-cli` OpenCode skill documents the `sentry` command for `suremac` agents. Keep credentials out of Nix/plaintext docs: use `sentry auth login` and the CLI-managed `~/.sentry/` database. Update through `update-flakes --manual-packages-only --manual-package sentry --manual-version sentry=<version>` so the version and npm tarball hash change together.

Linear CLI is installed on `suremac` from the `linear-cli` flake input via the `dotfiles.linearCli` Home Manager module. The module installs static completions and merges non-secret agent context into the CLI's user-level `config.toml` during activation while preserving keyring-backed auth/profile metadata; it also writes the org SDLC hygiene ruleset to the CLI's user-level `hygiene.toml` for `linear hygiene check`. The CLI's user config dir is platform-resolved (`~/Library/Application Support/linear-cli` on macOS, `$XDG_CONFIG_HOME/linear-cli` on Linux); do not write to `~/.config/linear-cli` on macOS. Keep Linear credentials out of Nix/plaintext docs; use `linear auth login`. The configured context should stay high-level (team/status defaults, label-group policy, estimation rubric, and agent instructions) and should not embed private member mappings or full internal taxonomies; agents should fetch current options with `linear context options ... --output json --compact` when needed.

`dotfiles.linearCli.hygieneAutomation` (enabled on `suremac`, Darwin-only) automates the Linear hygiene loop around the local `hygiene-last-run.json` check artifact: weekday launchd jobs refresh the report cache at 10:00/16:00, notify at 16:05 when high/medium findings exist, run an hourly 9:30-18:30 watch that notifies about newly seen high findings (deduped in `~/.local/state/linear-hygiene/`), and run `linear-hygiene-autofix` at 10:20/16:20. The autofix job only handles low-stakes rules (domain/type label, estimate, priority): it batches findings plus issue context into one prompt for a cheap agent harness (`opencode run --model openrouter/openai/gpt-5.5 --variant low` by default, swappable via `autofix.agentCommand`), then validates every decision against allowed values and applies them itself via `linear i update`; label updates merge existing labels because `-l` replaces the label set. Shell integration adds a starship `⚑high ~medium` prompt hint and a fun new-shell greeting rate-limited only within the same minute (`LINEAR_HYGIENE_GREETING=0` disables). Logs: `~/Library/Logs/linear-hygiene-*.log`. See `docs/linear-cli.md`.

Granola CLI is packaged from the SourceHut `granola-cli` flake input and enabled only for `suremac` via `dotfiles.granola`. Its token lives in `secrets/granola-token.age` and Home Manager activation seeds the CLI's OS keyring on first run with `granola auth login --key-stdin --validate`; agents should not read or print the decrypted token. `suremac` also exposes `granola` through `dotfiles.opencode.agentTools` so OpenCode agents know the CLI is available, and installs the `granola-meeting-context` skill for concise, redacted meeting-note context lookups.

Granola CLI v0.8 uses consistent note subcommands: use `granola notes search`, `granola notes get`, and `granola notes open` instead of the removed top-level `search`/`show`/`open` aliases. Use singular `--include-transcript` for syncs and multi-note/context reads that expose the flag. `granola context` and `granola notes get-many` require an explicit selector such as note IDs/URLs, `--notes-file`, `--stdin`, list filters, or `--all`; do not call them bare and assume the first page will be selected. Use `granola notes fields [list|search|get]` to discover valid fields, `--output text`/single-field output for shell pipelines, and `granola notes get NOTE --fields transcript` when transcript text is needed. Use `granola export note NOTE --format text` for single-note text exports.

Upstream OpenCode's flake builds `opencode-node_modules` as a fixed-output derivation from `nix/hashes.json`; the fast-moving dev branch can temporarily publish stale hashes or inconsistent `bun.lock` entries. Keep any local node-modules override in the base-lib OpenCode overlay scoped by full upstream revision and system, and mirror it in the hm-modules standalone overlay if needed. If the override patches the lockfile, also update the fixed-output hash for the patched system and drop the override once upstream catches up.

## Changelog Policy

- **Canonical source**: The `jj describe` message is the changelog entry
- **Format**: Keep entries concise; sparing Markdown allowed (short sentences, optional inline code)
- **Splitting changes**: Break disparate changes into separate commits using `jj split`, `jj squash`
- **Style**: Use type/scope prefix (e.g., `feat(opencode): add changelog policy`)
- **Agent consumption**: The changelog agent reads this policy from `AGENTS.md`

## CI (SourceHut)

Jobs in `.builds/` run in parallel on push. SourceHut limits: **4 concurrent jobs**, **5 min timeout** per job.

| Job | Purpose |
|-----|---------|
| `lint-check.yml` | alejandra, statix, `nix flake check` |
| `build-suremac.yml` | Darwin flake validation (`--no-build` on Linux) |
| `build-tom.yml` | Build tom NixOS config |
| `build-trap.yml` | Build trap NixOS config |
| `build-thorny.yml` | Build thorny NixOS config |
| `build-cruber.yml` | Build cruber NixOS config |

**Note**: Inactive hosts (taz, tootsie) are intentionally excluded from CI. They remain in the repo for reference but are not actively maintained or deployed. Adding CI for them would consume limited SourceHut job slots without benefit.

**Critical**: Never track `result` symlinks—they point to local store paths and break CI. See `.gitignore` patterns: `/result`, `/result-*`, `flakes/hosts/*/result`.

## Troubleshooting

See `docs/troubleshooting/` for common issues and solutions:

- **Sudo/setuid broken (`nobody:nogroup` ownership)**: If `sudo` fails with permission errors and `/run/wrappers/bin/sudo` is owned by `nobody:nogroup`, see `docs/troubleshooting/sudo-setuid-nobody-nogroup.md`. This typically occurs when NixOS was installed from within a user namespace.
- **GPG agent lock / keyboxd timeout**: If jj or git fails with "waiting for lock" errors, see `docs/troubleshooting/gpg-agent-lock.md`. The cleanup service should run automatically on login.
- **MT7925e Wi-Fi instability on tater**: If `tater` randomly loses connectivity and only recovers after a reboot, see `docs/troubleshooting/mt7925e-network-instability.md` for mitigation details, log collection, and non-reboot recovery steps.

## Host-Specific Notes

| Host | System | Notes |
|------|--------|-------|
| suremac | aarch64-darwin | Use `darwin-rebuild`, not deploy-rs |
| trap | x86_64-linux | COSMIC desktop, System76 |
| thorny | x86_64-linux | COSMIC desktop, System76 Thelio |
| tom | x86_64-linux | Requires openssl-1.1.1w for home-assistant |
| cruber | x86_64-linux | COSMIC desktop, Dell XPS |
| trainwreck | aarch64-linux | Hetzner VPS, runs openclaw (Telegram AI assistant) |
| taz | x86_64-linux | Inactive, Linode VM, Searx |
| tootsie | x86_64-linux | Inactive, Linode VM, Tailscale exit node |

## Openclaw (trainwreck)

Openclaw is a Telegram AI assistant running on trainwreck. Configuration is in `flakes/hosts/trainwreck/configuration.nix`.

### Instances

There are two openclaw instances running on trainwreck:

| Instance | Service | Purpose |
|----------|---------|---------|
| `grem` | `openclaw-gateway-grem.service` | Production bot |
| `grem-staging` | `openclaw-gateway-grem-staging.service` | Testing config changes |

The Home Manager Openclaw package overrides `meta.priority = 10`. Keep this
priority override: the Openclaw bundle and the shared shell Python both expose
`bin/python-config`, and equal-priority installation causes `home-manager-path`
buildEnv collisions during trainwreck builds.

**Development workflow**: Always make config changes to `instances.grem-staging` first, deploy, and test with the staging Telegram bot. Once verified working, copy the changes to `instances.grem` and deploy again.

### Service Management

```bash
# Production bot
systemctl --user status openclaw-gateway-grem.service
systemctl --user restart openclaw-gateway-grem.service
journalctl --user -u openclaw-gateway-grem.service -f

# Staging bot (use for testing config changes)
systemctl --user status openclaw-gateway-grem-staging.service
systemctl --user restart openclaw-gateway-grem-staging.service
journalctl --user -u openclaw-gateway-grem-staging.service -f
```

**Note**: SSH access from suremac requires the trainwreck public IP (ask the user). Other hosts can use `ssh chris@trainwreck` via Tailscale.

### Directory Structure on trainwreck

| Path | Purpose |
|------|---------|
| `~/.openclaw-grem/` | Grem production state directory |
| `~/.openclaw-grem/openclaw.json` | Config symlink (points to nix store) |
| `~/.openclaw-grem/runtime/openclaw-grem.json` | Runtime config (generated) |
| `~/.openclaw-grem/extensions/` | Symlink to `~/dotfiles/flakes/hosts/trainwreck/clawdbot-extensions/` |
| `~/.openclaw-grem/telegram/` | Telegram session state |
| `~/.openclaw-grem/agents/` | Agent configurations |
| `~/.openclaw-grem/workspace/` | Workspace files
| `/tmp/openclaw/openclaw-gateway.log` | Service log file |

### Personality Documents (Encrypted)

Grem's personality documents are encrypted with agenix (contain personal info):

| Secret | Purpose |
|--------|---------|
| `secrets/trainwreck/grem-AGENTS.md.age` | Agent instructions, security protocol, multi-user awareness |
| `secrets/trainwreck/grem-SOUL.md.age` | Personality, identity, relationship context |
| `secrets/trainwreck/grem-TOOLS.md.age` | Tool documentation and usage guidelines |

**To edit documents:**
```bash
cd ~/dotfiles/secrets
agenix -e trainwreck/grem-AGENTS.md.age  # Opens in $EDITOR
agenix -e trainwreck/grem-SOUL.md.age
agenix -e trainwreck/grem-TOOLS.md.age
```

Documents are decrypted at activation time and symlinked to `~/.openclaw-grem/workspace/`.

### Custom Extensions

Extensions live in `flakes/hosts/trainwreck/clawdbot-extensions/`:

- `kagi-search/` - Kagi search integration
- `meme-generator/` - Meme generation (imgflip + AI)
- `image-generator/` - AI image generation (profile pics, artwork)
- `opencode-delegate/` - Delegate coding tasks to opencode

**Important**: After pushing changes to extensions, you must also pull on trainwreck:

```bash
ssh chris@<trainwreck-ip> "cd ~/dotfiles && git pull"
systemctl --user restart openclaw-gateway-grem.service
```

### Session Isolation

Each DM conversation gets its own isolated session (`session.dmScope = "per-peer"`). This means:

- Your girlfriend has her own session with Grem (separate context/memory)
- Other users each get their own isolated session
- Group chats have their own sessions (separate from DMs)

**Identity Links** allow you to share a session across platforms. Your Telegram ID is linked under `chris`:

```nix
session.identityLinks = {
  chris = ["telegram:7281917558"];
};
```

**To add more platforms** (Discord, Signal, Slack, etc.), add them to the list:

```nix
session.identityLinks = {
  chris = [
    "telegram:7281917558"
    "discord:YOUR_DISCORD_USER_ID"
    "signal:+15551234567"
    "slack:YOUR_SLACK_USER_ID"
  ];
};
```

This way all your DMs across platforms share the same session context.

### Deploying trainwreck

Deploy trainwreck with deploy-rs from this repository:

```bash
nix run .#deploy -- .#trainwreck
```

For quieter deploys, use the wrapper app. It runs only the target host flake
check first, then invokes deploy-rs with its broad checks skipped. Both phases
buffer output and only print full logs on failure:

```bash
nix run .#deploy-quiet -- trainwreck
nix run .#deploy-quiet -- --no-checks trainwreck          # skip even the host check
nix run .#deploy-quiet -- --deploy-rs-checks trainwreck   # use deploy-rs checks instead
nix run .#deploy-quiet -- --show-output trainwreck        # stream logs live
```

The shared `mkDeploy` helper selects the deploy-rs activation wrapper for the
target host architecture, so trainwreck's activation wrapper is `aarch64-linux`.
Keep this architecture selection intact: using an x86_64 activation wrapper for
trainwreck copies a non-ARM binary to the host and fails during activation with
`cannot execute binary file: Exec format error`.

If deploy-rs is unavailable, fall back to rebuilding on trainwreck directly:

```bash
ssh chris@<trainwreck-ip> "cd ~/dotfiles && git pull && sudo nixos-rebuild switch --flake .#trainwreck"
```
