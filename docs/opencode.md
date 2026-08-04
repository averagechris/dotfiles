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
- repo-managed skills deployed into `~/.config/opencode/skills/`
- MCP server definitions written into the generated OpenCode config
- optional `OPENROUTER_API_KEY` shell export via `dotfiles.opencode.openrouterApiKeyFile`
- optional `CIRCLECI_TOKEN` shell export via `dotfiles.opencode.circleciTokenFile`
- agent-specific runtime packages and prompt metadata exposed via `dotfiles.opencode.agentTools`
- host-specific private skill appendices materialized during Home Manager activation
- on hosts with `dotfiles.devCache`, an automatically loaded `shell.env` plugin
  sets `CARGO_INCREMENTAL=0` only inside OpenCode so parallel isolated Rust
  workspaces favor the shared sccache without changing interactive shells

## Declarative CLI skills

CLI modules register bundled skills in the shared `dotfiles.agentSkills`
registry. Every registered skill is enabled by default and Home Manager links
the rendered result at `~/.config/opencode/skills/<name>/SKILL.md` when OpenCode
is enabled. Hosts can customize each skill independently:

```nix
dotfiles.agentSkills.rdny-browser = {
  enable = true;
  patches = [./rdny-browser.patch];
  extraText = ''
    ## Host workflow

    Use the host browser wrapper for visible sessions.
  '';
};

dotfiles.agentSkills.gander-address-review.enable = false;
```

The renderer copies the upstream `source`, applies `patches` in order with zero
fuzz, then appends `extraText`. Use a patch when changing or removing upstream
instructions; its build failure intentionally detects upstream drift. Use
`extraText` only for additive local guidance. CLI modules own source
registration, while hosts normally set only `enable`, `patches`, or `extraText`.

New CLI modules should import `agent-skills.nix` and register every bundled skill
with a default source; they should not add bespoke skill options or activation
scripts:

```nix
{
  config,
  lib,
  ...
}: let
  cfg = config.dotfiles.exampleCli;
  skillSourceDirectory =
    if cfg.package != null && cfg.package ? src
    then cfg.package.src + "/skills"
    else null;
in {
  imports = [./agent-skills.nix];

  config = lib.mkIf cfg.enable {
    dotfiles.agentSkills.example.source = lib.mkDefault (
      if skillSourceDirectory == null
      then null
      else skillSourceDirectory + "/example/SKILL.md"
    );
    dotfiles.agentSkillBundles.example-cli = {
      sourceDirectory = lib.mkDefault skillSourceDirectory;
      expectedNames = ["example"];
    };
  };
}
```

Use one registry entry per skill rather than a names allowlist. This makes every
new skill available by default while preserving stable host overrides such as
`dotfiles.agentSkills.example.enable = false`.

Every package-backed registration must also declare an audited
`dotfiles.agentSkillBundles` manifest. The default `directories` layout discovers
`<name>/SKILL.md`; `layout = "flat-markdown"` discovers `<name>.md`. Evaluation
fails when discovered and expected names differ, reporting additions and
removals separately. Package upgrades therefore cannot silently expose or omit a
skill: review the changed upstream skill set, update `expectedNames`, ensure each
name has a registry entry, then keep its default enablement, patch it, or disable
it explicitly.

On Linux, the module wraps the OpenCode package with `LD_LIBRARY_PATH` pointing
at `stdenv.cc.cc.lib`. This makes OpenCode's native file-watcher binding able to
find `libstdc++.so.6` on NixOS. Without the wrapper, OpenCode may log or surface
startup failures while loading project or global files, including custom tools.

## Agent-exposed tools

The OpenCode module installs a small, explicit set of agent-specific tools and
generates the system-prompt tool note from the configured list when
`programs.opencode.enable = true`. Hosts that leave OpenCode disabled do not get
the agent runtime tools or generated OpenCode config files in their Home Manager
profile.

The `orchestrator` is the generated OpenCode default agent, making decomposition
and Minion-first routing the normal entry point. It uses the same open-by-default
bash safety posture as Build and is tuned for ambitious projects
and can delegate work across five coding tiers: `tiny`, `luna`, `minion`,
`build`, and `wise`. Tiny uses GPT-5.6 Luna at `low` for mechanical work, while
the distinct Luna tier uses the same model at `high` for bounded work requiring
more reasoning. Minion uses GPT-5.6 Sol at `low` and is the default implementation
tier: the orchestrator decomposes work and supplies clear implementation packets
so Minion performs the bulk of coding. Build is reserved for ambiguity, breadth,
investigation, or coordination that planning cannot reasonably remove. The
higher-capability `wise` agent uses `openrouter/anthropic/claude-fable-5` with
`variant = "high"`. All coding agents share one generated bash permission
policy so safety-rule changes stay consistent across tiers. Their concise
descriptions summarize the intended delegation tradeoff so primary agents can
choose effectively from the task tool.

The repo-managed `subagent-selection` skill and orchestrator both render the
canonical routing policy from `agent-selection-policy.md` and the relative
intelligence, taste, speed, and cost scorecard from
`agent-selection-table.md`. The policy defines tier boundaries, residual
uncertainty handoffs, escalation, review limits, and finding severity gates;
update those shared sources rather than restating the rules in consumers or
documentation. The scorecard describes relative qualities rather than a utility
ranking: routing favors the least expensive tier likely to succeed once it meets
the task's capability threshold. Its canonical rubric defines capability bands,
intrinsic response speed at comparable work, and nonlinear intrinsic model-cost
bands independently of the tasks each tier is assigned.

The built-in `explore` subagent keeps its upstream prompt and tools but is
configured through `settings.agent.explore` to use
`openrouter/openai/gpt-5.6-luna` with the `medium` variant. This favors cheap,
parallel codebase research with a research-specific prompt and tool set; Tiny
remains narrower and mechanical, while Luna handles bounded reasoned work.

OpenCode normally prompts before any tool touches a path outside the project it
was started in. To keep delegated coding work smooth without opening up entire
project trees, the Home Manager module derives
`permission.external_directory` allow rules from
`dotfiles.jujutsu.workspaces.projectGroups`: each canonical managed workspace
namespace (`<project-group>/<workspace-dir>/**`, such as `~/projects/ws/**` and
on `suremac` also `~/sureapp/ws/**`) is trusted by default. This covers files
created by `jj ws add` while preserving prompts for unrelated external
directories.

The same external-directory policy allows read/search access to package sources
and build outputs under `/nix/store`, general temporary files under `/tmp` and
`/private/tmp`, plus OpenCode's session-specific directories under
`/var/folders/**/T/opencode` and `/private/var/folders/**/T/opencode`. The Nix
store is immutable to normal users, so allowing the external path lets agents
use OpenCode reads and searches or commands such as `rg` there without granting
them a practical write path. Both temporary-path spellings are present because
macOS canonicalizes `/tmp` and `/var` through `/private`; unrelated external
directories continue to prompt.

For Build, `orchestrator`, `minion`, `luna`, `tiny`, and `wise`, the catch-all rule is
`"*": "allow"`, and narrower later rules prompt or deny known sharp edges. OpenCode
evaluates the last matching permission rule, so keep the broad allow at the top
and add riskier overrides below it. This reduces approval fatigue for normal
build/test/exploration work while keeping rare high-impact decisions visible.

Prompt-gated Build-agent command families include:

- reads of encrypted secret material via common text/search commands, plus
  `.env*`, `agenix`, and `sops`; creating or updating encrypted secret files is
  still allowed so agents can run normal secret-editing workflows
- remote copy/login, deployment, and system switches (`ssh`, `scp`, `rsync`,
  `nix run .#deploy*`,
  `nixos-rebuild switch`, `darwin-rebuild switch`, `nh * switch`)
- privilege escalation (`sudo`, `doas`, `su`) is denied because it is not useful
  non-interactively and would require a human password anyway
- broad or sensitive deletion targets (`rm -rf /`, home-directory deletes, and
  secret-path deletes); ordinary relative cleanup and absolute cleanup beneath
  the trusted `/tmp`, `/private/tmp`, and OpenCode session-temp namespaces are
  allowed. The shared deletion-rule template can enable or omit those absolute
  temp exceptions independently for each agent.
- destructive ownership/permission/disk commands (`chmod`, `chown`, `chgrp`,
  `dd`, `diskutil`; `mkfs*` is denied)
- process/service control (`kill`, `killall`, `pkill`, `systemctl`,
  `launchctl`); Docker Compose teardown/prune commands remain allowed
- VCS history or publication operations (`git`, selected mutating `jj`
  subcommands, `jj push`, `jj ship`, `jj tag-push`)
- GitHub org/repo/auth/issue administration (`gh auth*`, `gh org*`,
  `gh repo*`, `gh issue*`)

For recursive temp cleanup, prefer a relative target with the Bash tool's
`workdir` set to the trusted temp directory. The absolute temp exceptions cover
common generated commands, while the external-directory allowlist remains a
second boundary for additional absolute operands. Bash permission wildcards are
guardrails against routine mistakes, not an argument-aware shell sandbox.

Host-exposed browser automation follows the open default: `rdny` commands are
allowed for Build agents unless they hit a later risky pattern.

Host-specific investigation CLIs follow the same prompt-reduction model. The
Build agent allows `pup`, `sentry`, and read-oriented `kubectl` investigation by
default. Kubernetes secret reads/describes and mutating/session-like subcommands
such as `apply`, `delete`, `edit`, `exec`, `patch`, `port-forward`, and
`rollout` are prompt-gated by explicit overrides. Prefer subcommand-first
kubectl invocations such as `kubectl get pods -n namespace` so the narrow
override rules can still catch risky subcommands.

When adding command allow rules, prefer an exact command plus a command-space
wildcard, for example `tool` and `tool *`. Avoid bare prefix allow patterns such
as `tool*`, because they also match unrelated executable names like
`tool_malicious`. Conservative `ask`/`deny` override rules can be broader when
the intent is to interrupt anything in that command family.

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
derivation from `nix/hashes.json`. Because the `dev` branch moves quickly, the
source, `bun.lock`, and node-modules hashes can temporarily drift from each
other. The base-lib overlay carries any required per-revision node-modules
overrides next to the upstream package selection, including narrow lockfile
patches when needed. Overrides are scoped by full upstream revision and system so
future upstream fixes are used automatically.

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
- `python3` - Python runtime
- `rg` - fast code search

These come from the module's built-in default tool list:

```nix
[
  { package = jujutsu; name = "jj"; description = "Jujutsu VCS"; }
  { package = nodejs; name = "nodejs"; description = "JavaScript runtime"; }
  { package = python3Minimal; name = "python3"; description = "Python runtime"; }
  { package = ripgrep; name = "rg"; description = "fast code search"; }
]
```

The Python entry intentionally uses the minimal interpreter package. It is enough
for ad hoc agent scripts and avoids retaining the full Darwin compiler/SDK
closure through the standard Python build on macOS. Use a project dev shell for
workflows that need extra Python packages or a specific interpreter version.

Each entry defines:

- the package to install in `home.packages`
- the tool name to mention in the primary agent prompts
- an optional extremely brief description when the name alone is not enough

Hosts append additional tools via `dotfiles.opencode.agentTools`, and the
module combines those with the built-in default tool list.

### Host-specific additions

Use `dotfiles.opencode.agentTools` for tools that should only be available to
agents on particular hosts. For example, `suremac` adds the AWS CLI, Ctx,
Kubernetes CLI, Datadog Pup CLI, Sentry CLI, GitHub CLI, rdny, Showboat,
Granola, Sideshow, and the Linear CLI. On Darwin, this host-specific list avoids
relying on unrelated system packages for agent workflows:

```nix
dotfiles.opencode.agentSupportPackages = [];

dotfiles.opencode.agentTools = with pkgs; [
  { package = awscli2; name = "aws"; description = "AWS CLI"; }
  {
    package = inputs.ctx.packages.${pkgs.stdenv.hostPlatform.system}.ctx;
    name = "ctx";
    description = "agent history search CLI";
  }
  { package = kubectl; name = "kubectl"; description = "Kubernetes CLI"; }
  { package = pup; name = "pup"; description = "Datadog CLI"; }
  { package = sentry; name = "sentry"; description = "Sentry CLI"; }
  { package = notion-cli; name = "ntn"; description = "Notion CLI"; }
  { package = gh; name = "gh"; description = "GitHub CLI"; }
  { package = showboat; name = "showboat"; description = "work documentation CLI"; }
  {
    package = inputs.linear-cli.packages.${pkgs.stdenv.hostPlatform.system}.linear;
    name = "linear";
    description = "Linear CLI";
  }
  {
    package = inputs.granola-cli.packages.${pkgs.stdenv.hostPlatform.system}.default;
    name = "granola";
    description = "Granola meeting notes CLI";
  }
  {
    package = inputs.sideshow.packages.${pkgs.stdenv.hostPlatform.system}.sideshow;
    name = "sideshow";
    description = "HTML slide deck CLI";
  }
];
```

Tool-specific modules can append their own entries too. `dotfiles.rdny` appends
`rdny` and registers the `rdny-browser` skill when enabled.

Primary agent prompts render a concise structured runtime note dynamically, for
example:

> Your runtime is a macOS environment. By default, your environment includes
> these additional tools: jj (Jujutsu VCS), nodejs (JavaScript runtime),
> python3 (Python runtime), rg (fast code search), aws (AWS CLI), ctx (agent
> history search CLI), kubectl (Kubernetes CLI), pup
> (Datadog CLI), sentry (Sentry CLI), ntn (Notion CLI), gh (GitHub CLI), showboat
> (work documentation CLI), linear (Linear CLI), granola (Granola meeting notes
> CLI), sideshow (HTML slide deck CLI), rdny (browser automation CLI). The
> project local dev shell may provide additional tooling.

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

## Installed skills

This repo also ships local skills for common tool-specific workflows. CLI
modules register bundled or repo-managed skills with `dotfiles.agentSkills`, so
rendering, patching, extension, and per-skill enablement happen uniformly at
build time. Current examples include:

- `jj-vcs`
- `jj-change-management`
- `jj-conflict-resolution`
- `jj-repo-workflow`
- `jj-workspaces`
- `linear-cli`
- `linear-admin`, `linear-data`, `linear-git`, `linear-issues`,
  `linear-organization`, `linear-planning`, and `linear-tracking` (registered by
  `dotfiles.linearCli`)
- `rdny-browser` (registered by `dotfiles.rdny`)
- `gander-review` and `gander-address-review` (registered by `dotfiles.gander`)
- `sideshow-work-story` (registered by `dotfiles.sideshow`)
- `srht-issues`, `srht-ci`, and `srht-setup` (registered by `dotfiles.srht`)
- `databricks-cli`
- `pup-cli`
- `sure-stack-context` (suremac only)

Home Manager activation removes files left by the retired OpenCode PR-review
tools from `~/.config/opencode/tools/`.

The `databricks-cli` skill explains an important CLI detail: there is no
top-level `databricks sql` subcommand in the current official CLI. Agents
should use `queries`, `query-history`, `warehouses`, `psql`, or `databricks api`
depending on the task.

`suremac` additionally configures the `granola-meeting-context` skill so agents can pull
concise, redacted meeting-note context with the host-specific `granola` CLI when
relevant. The host-specific `pup-cli` skill gives agents compact Datadog CLI
patterns centered on `--read-only`, `--no-agent`, `--jq`, bounded queries, and
CSV/JSON output selection. `suremac` also installs `sure-stack-context`, a
Sure-specific investigation skill that routes between Datadog, Sentry, and
Kubernetes tools. Its company-specific service/ecosystem appendix is decrypted
from `secrets/opencode-sure-stack-context.age` and appended only to the local
installed skill, not stored in public docs or skill sources.

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
