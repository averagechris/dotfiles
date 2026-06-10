# OpenCode

This repository manages OpenCode through the home-manager module at `flakes/hm-modules/modules/opencode/`.

OpenCode itself comes from the upstream `github:anomalyco/opencode` flake input,
not from nixpkgs. `flakes/base-lib/` exposes that package through the shared
overlay as `pkgs.opencode`, and `flakes/hm-modules/` mirrors the same overlay for
standalone module evaluation checks. This keeps OpenCode closer to upstream's
frequent releases while preserving the normal `pkgs.opencode` and home-manager
`programs.opencode.package` integration points.

## What it configures

- custom primary and sub-agents
- repo-managed slash commands
- repo-managed skills deployed into `~/.config/opencode/skills/`
- repo-managed custom tools deployed into `~/.config/opencode/tools/`
- MCP server definitions written into the generated OpenCode config
- optional `OPENROUTER_API_KEY` shell export via `dotfiles.opencode.openrouterApiKeyFile`
- optional `CIRCLECI_TOKEN` shell export via `dotfiles.opencode.circleciTokenFile`
- agent-specific runtime packages and prompt metadata exposed via `dotfiles.opencode.agentTools`

On Linux, the module wraps the OpenCode package with `LD_LIBRARY_PATH` pointing
at `stdenv.cc.cc.lib`. This makes OpenCode's native file-watcher binding able to
find `libstdc++.so.6` on NixOS. Without the wrapper, OpenCode may log or surface
startup failures while loading project or global files, including custom tools.

## Agent-exposed tools

The OpenCode module installs a small, explicit set of agent-specific tools and
generates the system-prompt tool note from the configured list.

The Build primary agent also has a bash permission allowlist for common
development commands. Build runners such as `just` and `make` are allowed so
agents can execute repository-provided workflows without prompting for each
invocation.

### Env-prefixed runner commands

OpenCode currently evaluates bash permission rules against the command source it
extracts from the shell AST. For inline environment assignments, that source can
include the assignments, so a command such as:

```bash
SERVICE_REDIS_PORT=51820 SERVICE_POSTGRES_PORT=51821 just test ...
```

does not match the existing `"just *": "allow"` rule. The prompt may still offer
an "always" approval for `just *`, but that session approval does not cover the
next env-prefixed invocation because the evaluated pattern still starts with the
assignment prefix.

This module patches `pkgs.opencode`, which is supplied by the upstream OpenCode
flake overlay, with module-local patches under
`flakes/hm-modules/modules/opencode/patches/`.

`opencode-strip-env-assignments.patch` normalizes bash permission patterns by
stripping safe leading inline environment assignments before permission
matching. With the example above, OpenCode authorizes `just test ...`, so the
existing `just` and `just *` allow rules work across projects no matter what
service-specific environment prefix they use.

The patch deliberately does not strip assignments containing command
substitution, such as `FOO=$(curl example.com) just test` or backticks. Those
assignments can execute code before `just` starts and should fall through to the
normal catch-all prompt.

The upstream OpenCode flake builds a fixed-output `opencode-node_modules`
derivation from `nix/hashes.json`. Because the `dev` branch moves quickly, that
hash can temporarily lag the lockfile revision. The base-lib overlay carries any
required per-revision node-modules hash overrides next to the upstream package
selection, scoped by full upstream revision so future upstream hash updates are
used automatically.

Prefer this normalization patch over broad config patterns such as `*=* just *`.
OpenCode permission wildcards are anchored but simple (`*` and `?` only), so a
broad assignment-style pattern can accidentally match unrelated commands that
merely contain `=... just ...` in their arguments.

`opencode-allow-nix-bun-1-3-13.patch` keeps the upstream build working while
nixpkgs' packaged Bun briefly lags the Bun patch version declared in OpenCode's
root `package.json`. It broadens the build script's version guard to accept the
same Bun 1.3 minor series provided by the Nix toolchain; remove it once nixpkgs
and upstream agree on the same Bun patch release.

Agent-exposed tools and MCPs are configured separately:

- `dotfiles.opencode.agentTools` installs CLI tools into `home.packages` and
  mentions them in the primary agent runtime note.
- `dotfiles.opencode.agentSupportPackages` installs supporting packages into
  `home.packages` without mentioning them in the runtime note.
- `programs.opencode.settings.mcp` configures MCP servers in OpenCode itself;
  these are integrations the agent can use when enabled, but they are not part
  of the runtime-note tool list by default.

### Shared core packages

By default, all OpenCode-enabled hosts install:

- `jj` - Jujutsu VCS
- `nodejs` - JavaScript runtime
- `python3` - Python 3.14 runtime
- `rg` - fast code search

These come from the module's built-in default tool list:

```nix
[
  { package = jujutsu; name = "jj"; description = "Jujutsu VCS"; }
  { package = nodejs; name = "nodejs"; description = "JavaScript runtime"; }
  { package = python314; name = "python3"; description = "Python 3.14 runtime"; }
  { package = ripgrep; name = "rg"; description = "fast code search"; }
]
```

Each entry defines:

- the package to install in `home.packages`
- the tool name to mention in the primary agent prompts
- an optional extremely brief description when the name alone is not enough

Hosts append additional tools via `dotfiles.opencode.agentTools`, and the
module combines those with the built-in default tool list.

### Host-specific additions

Use `dotfiles.opencode.agentTools` for tools that should only be available to
agents on particular hosts. For example, `suremac` adds the CircleCI CLI,
CodeRabbit CLI, Databricks CLI, GitHub CLI, Rodney, Showboat, and the Linear
CLI. On Darwin, this host-specific list avoids relying on unrelated system
packages for agent workflows:

```nix
dotfiles.opencode.agentSupportPackages = with pkgs; [
  python313Packages.databricks-sql-connector
];

dotfiles.opencode.agentTools = with pkgs; [
  { package = circleci-cli; name = "circleci"; description = "CircleCI CLI"; }
  { package = coderabbit-cli; name = "cr"; description = "CodeRabbit AI review CLI"; }
  { package = databricks-cli; name = "databricks-cli"; }
  { package = gh; name = "gh"; description = "GitHub CLI"; }
  { package = rodney; name = "rodney"; description = "Chrome automation CLI"; }
  { package = showboat; name = "showboat"; description = "work documentation CLI"; }
  {
    package = inputs.linear-cli.packages.${pkgs.stdenv.hostPlatform.system}.linear;
    name = "linear";
    description = "Linear CLI";
  }
];
```

Primary agent prompts render a concise structured runtime note dynamically, for
example:

> Your runtime is a macOS environment. By default, your environment includes
> these additional tools: jj (Jujutsu VCS), nodejs (JavaScript runtime),
> python3 (Python 3.14 runtime), rg (fast code search),
> circleci (CircleCI CLI), cr (CodeRabbit AI review CLI), databricks-cli,
> gh (GitHub CLI), rodney (Chrome automation CLI),
> showboat (work documentation CLI), linear (Linear CLI). The project local dev
> shell may provide additional tooling.

Use `agentSupportPackages` for dependencies that a visible tool needs under the
hood but that the agent does not need to call directly.

## MCP integrations

All MCP servers are defined in `flakes/hm-modules/modules/opencode/settings.nix` and default to `enabled = false` unless explicitly turned on.

| MCP server | Type | Default | Notes |
|------------|------|---------|-------|
| `context7` | remote | disabled | Documentation lookup |
| `circleci` | local | disabled | Launches `@circleci/mcp-server-circleci` via the module's Node-aware `npx` wrapper; requires `CIRCLECI_TOKEN` when enabled |
| `datadog` | remote | disabled | Datadog MCP endpoint |
| `gh-grep` | remote | disabled | GitHub code search via Grep |
| `github` | remote | disabled | GitHub Copilot MCP endpoint |
| `playwright` | local | disabled | Launches `@playwright/mcp` via the module's Node-aware `npx` wrapper for browser automation |
| `notion` | remote | disabled | Hosted Notion MCP endpoint using OAuth |
| `serena` | local | disabled | Launched via `uvx` from the upstream repository |
| `sentry` | remote | disabled | Hosted Sentry MCP endpoint using OAuth |

## Repo-managed skills

This repo also ships a small set of local skills for common tool-specific
workflows. Current examples include:

- `jj-vcs`
- `jj-change-management`
- `jj-conflict-resolution`
- `jj-repo-workflow`
- `jj-workspaces`
- `changes-review-core`
- `github-pr-review`
- `linear-cli`
- `databricks-cli`

The PR review workflow is split into a reusable core review skill plus a
GitHub-specific wrapper. Supporting custom tools live under `.opencode/tools/`.
They are materialized as writable files in `~/.config/opencode/tools/`, and
`programs.opencode.tools` points OpenCode at that config-directory copy rather
than at the Nix store source path. This keeps TypeScript imports resolving from
the user config directory instead of `/nix/store`. The module also writes a
minimal `~/.config/opencode/package.json` declaring `@opencode-ai/plugin`; this
lets OpenCode populate `~/.config/opencode/node_modules` before importing custom
tools. The tools currently include:

- `review-artifact-generate` - draft artifact bootstrapper from GitHub metadata and diff text
- `review-artifact-write` - strict artifact validation and temp-file persistence
- `review-artifact-render` - compact terminal digest renderer for persisted artifacts
- `review-github-post` - explicit-confirmation batched GitHub review submission

See [opencode-pr-review](/docs/opencode-pr-review.md) for the full workflow and design notes.

The `databricks-cli` skill explains an important CLI detail: there is no
top-level `databricks sql` subcommand in the current official CLI. Agents
should use `queries`, `query-history`, `warehouses`, `psql`, or `databricks api`
depending on the task.

`suremac` additionally configures the repo-managed `coderabbit-cli` skill for
its OpenCode agents only, alongside the host-specific `cr`/`coderabbit` package.
It also configures the `granola-meeting-context` skill so agents can pull
concise, redacted meeting-note context with the host-specific `granola` CLI when
relevant.

The jj skills recommend quiet/structured helper output for agents, especially
`jj sync -q --fail-on-conflicts` and `jj sync --json --fail-on-conflicts`.
When `jj lint` is not configured, agents should run `jj lint onboard --print`
to discover numbered candidate package, Python pyproject/tox/nox, Makefile,
justfile, Docker Compose, docs, CI, and pre-commit replacement workflows before
skipping validation. If only some suggestions are appropriate, persist exactly
those with `jj lint onboard --preview --select=1,3`, then persist with
`jj lint onboard --local --select=1,3` or
`jj lint onboard --write --select=1,3`.
Tracked `.jj-lint.toml` entries may be strings or `{ name, command }` tables;
omit `name` to use the inferred display label.

## OpenRouter API key

To provide an API key non-interactively, set:

```nix
dotfiles.opencode.openrouterApiKeyFile = "/run/agenix/openrouter-api-key";
```

The module exports `OPENROUTER_API_KEY` from that file in both Bash and Zsh shell initialization.

## CircleCI token

To provide a CircleCI token non-interactively, set:

```nix
dotfiles.opencode.circleciTokenFile = "/run/agenix/circleci-token";
```

The module exports `CIRCLECI_TOKEN` from that file in both Bash and Zsh shell initialization. This supports the `circleci` CLI and the optional OpenCode CircleCI MCP integration when enabled.

Local MCP servers that are distributed as npm packages use a repo-managed
`opencode-npx-mcp` wrapper instead of calling the Nix store `npx` executable
directly. The wrapper puts `node` on `PATH` for the MCP child process, which is
required because npm's `npx` launcher uses `/usr/bin/env node` internally.

On `suremac`, this relies on nix-darwin agenix secret materialization. The host
config sets explicit `age.identityPaths` for the user's SSH keys so Darwin can
decrypt shared secrets into `/run/agenix/` during activation.
