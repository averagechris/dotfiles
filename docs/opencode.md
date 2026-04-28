# OpenCode

This repository manages OpenCode through the home-manager module at `flakes/hm-modules/modules/opencode/`.

## What it configures

- custom primary and sub-agents
- repo-managed slash commands
- repo-managed skills deployed into `~/.config/opencode/skills/`
- MCP server definitions written into the generated OpenCode config
- optional `OPENROUTER_API_KEY` shell export via `dotfiles.opencode.openrouterApiKeyFile`
- optional `CIRCLECI_TOKEN` shell export via `dotfiles.opencode.circleciTokenFile`
- agent-specific runtime packages and prompt metadata exposed via `dotfiles.opencode.agentTools`

## Agent-exposed tools

The OpenCode module installs a small, explicit set of agent-specific tools and
generates the system-prompt tool note from the configured list.

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
- `python3` - Python 3.13 runtime
- `rg` - fast code search

These come from the module's built-in default tool list:

```nix
[
  { package = jujutsu; name = "jj"; description = "Jujutsu VCS"; }
  { package = nodejs; name = "nodejs"; description = "JavaScript runtime"; }
  { package = python313; name = "python3"; description = "Python 3.13 runtime"; }
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
Databricks CLI, GitHub CLI, Rodney, Showboat, and the Linear CLI. On Darwin,
this host-specific list avoids relying on unrelated system packages for agent
workflows:

```nix
dotfiles.opencode.agentSupportPackages = with pkgs; [
  python313Packages.databricks-sql-connector
];

dotfiles.opencode.agentTools = with pkgs; [
  { package = circleci-cli; name = "circleci"; description = "CircleCI CLI"; }
  { package = databricks-cli; name = "databricks-cli"; }
  { package = gh; name = "gh"; description = "GitHub CLI"; }
  { package = rodney; name = "rodney"; description = "Chrome automation CLI"; }
  { package = showboat; name = "showboat"; description = "work documentation CLI"; }
  {
    package = inputs.linear-cli.packages.${pkgs.stdenv.hostPlatform.system}.homebrew-artifact;
    name = "linear";
    description = "Linear CLI";
  }
];
```

Primary agent prompts render a concise structured runtime note dynamically, for
example:

> Your runtime is a macOS environment. By default, your environment includes
> these additional tools: jj (Jujutsu VCS), nodejs (JavaScript runtime),
> python3 (Python 3.13 runtime), rg (fast code search),
> circleci (CircleCI CLI), databricks-cli, gh (GitHub CLI), rodney
> (Chrome automation CLI),
> showboat (work documentation CLI), linear (Linear CLI). The project local dev
> shell may provide additional tooling.

Use `agentSupportPackages` for dependencies that a visible tool needs under the
hood but that the agent does not need to call directly.

## MCP integrations

All MCP servers are defined in `flakes/hm-modules/modules/opencode/settings.nix` and default to `enabled = false` unless explicitly turned on.

| MCP server | Type | Default | Notes |
|------------|------|---------|-------|
| `context7` | remote | disabled | Documentation lookup |
| `circleci` | local | disabled | Launches `@circleci/mcp-server-circleci` via `npx`; requires `CIRCLECI_TOKEN` when enabled |
| `datadog` | remote | disabled | Datadog MCP endpoint |
| `gh-grep` | remote | disabled | GitHub code search via Grep |
| `github` | remote | disabled | GitHub Copilot MCP endpoint |
| `playwright` | local | disabled | Launches `@playwright/mcp` via `npx` for browser automation |
| `notion` | remote | disabled | Hosted Notion MCP endpoint using OAuth |
| `serena` | local | disabled | Launched via `uvx` from the upstream repository |
| `sentry` | remote | disabled | Hosted Sentry MCP endpoint using OAuth |

## Repo-managed skills

This repo also ships a small set of local skills for common tool-specific
workflows. Current examples include:

- `jj-vcs`
- `linear-cli`
- `databricks-cli`

The `databricks-cli` skill explains an important CLI detail: there is no
top-level `databricks sql` subcommand in the current official CLI. Agents
should use `queries`, `query-history`, `warehouses`, `psql`, or `databricks api`
depending on the task.

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

On `suremac`, this relies on nix-darwin agenix secret materialization. The host
config sets explicit `age.identityPaths` for the user's SSH keys so Darwin can
decrypt shared secrets into `/run/agenix/` during activation.
