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
- repo-managed slash commands deployed globally into `~/.config/opencode/commands/`, including `/what` for concise, jargon-free restatements
- MCP server definitions written into the generated OpenCode config
- optional `OPENROUTER_API_KEY` shell export via `dotfiles.opencode.openrouterApiKeyFile`
- optional `CIRCLECI_TOKEN` shell export via `dotfiles.opencode.circleciTokenFile`
- agent-specific runtime packages and prompt metadata exposed via `dotfiles.opencode.agentTools`
- host-specific private skill appendices materialized during Home Manager activation
- on hosts with `dotfiles.devCache`, an automatically loaded `shell.env` plugin
  sets `CARGO_INCREMENTAL=0` only inside OpenCode so parallel isolated Rust
  workspaces favor the shared sccache without changing interactive shells
- on hosts with direnv enabled, a `dotfiles-direnv` plugin loads each working
  directory's direnv-allowed dev shell environment into agent shell commands

## Repo-managed slash commands

The pinned Home Manager OpenCode module supports `programs.opencode.commands`
with command names mapped to inline text or Markdown files. This module maps
the repo-managed `commands/what.md` to the global `/what` command. It asks
OpenCode to restate its last message plainly and concisely, and to use the
`impactful-writing` skill if needed.

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

The upstream `source` may be either one `SKILL.md` file or a complete skill
directory containing `SKILL.md`. Complete directories are copied recursively,
so Agent Skills companion content such as `assets/` and `references/` remains
available beside the instructions. The renderer applies `patches` in order with
zero fuzz specifically to `SKILL.md`, then appends `extraText` to `SKILL.md`;
companion files are left unchanged. A directory source without `SKILL.md` fails
evaluation or rendering clearly. File sources retain the existing one-file skill-directory
behavior and are not expanded to their parent directory, since flat Markdown
bundles can share one parent. Use a patch when changing or removing upstream
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

OpenCode's `subagent_depth` is set to `2`. Upstream counts a direct subagent at
depth one, so this permits one nested handoff while still preventing longer
delegation chains. The orchestrator policy requires every handoff prompt to say
whether sub-delegation is appropriate rather than adding situational guidance to
all delegated-agent prompts. Handoffs normally tell agents to complete their
packets directly; they may explicitly allow a sparse, separable handoff when it
is useful. Build may re-delegate sparingly when unresolved complexity warrants
it. Minion is more tightly scoped: its task permissions allow only Explore for
focused research and Tiny for mechanical support, not coding agents for
implementation or build work. Handoff prompts steer justified nested work
through the task tool and say not to use `opencode run` as a routine delegation
escape hatch. That command remains permission-allowed rather than banned.

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

Implementation packets require proof at the boundary where behavior is claimed.
Agents escalate when implementation disproves a design assumption, favor
subtraction unless added scope has a clear payoff, and use fresh scoped handoffs
when work or context no longer fits the packet.

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
- recursive deletion of absolute paths, the Bash tool's current work directory,
  upward traversal targets, home-directory targets, and secret paths. Ordinary
  relative cleanup beneath the Bash tool's `workdir` is allowed, including hidden
  children such as `.venv`. Absolute non-root descendants beneath `/tmp`,
  `/private/tmp`, and OpenCode session-temp trees under
  `/var/folders/**/T/opencode` and `/private/var/folders/**/T/opencode` are later
  allow-rule exceptions; deleting those temp roots themselves still prompts.
  The shared deletion-rule template can enable or omit those absolute temp
  exceptions independently for each agent.
- destructive ownership/permission/disk commands (`chmod`, `chown`, `chgrp`,
  `dd`, `diskutil`; `mkfs*` is denied)
- process/service control (`kill`, `killall`, `pkill`, `systemctl`,
  `launchctl`); Docker Compose teardown/prune commands remain allowed
- VCS history or publication operations (`git`, selected mutating `jj`
  subcommands, `jj push`, `jj ship`, `jj tag-push`)
- GitHub org/repo/auth/issue administration (`gh auth*`, `gh org*`,
  `gh repo*`, `gh issue*`)

For recursive cleanup, prefer a relative target with the Bash tool's `workdir`
set to the intended parent directory. This policy is a relative-to-tool-workdir
guardrail, not CWD sandboxing: OpenCode's simple command globs do not parse every
operand or prove that every relative path remains beneath the session's original
CWD, and the Bash tool's explicit `workdir` may differ from that CWD. The
absolute temp exceptions cover common generated commands, while the
external-directory allowlist remains a second boundary for additional absolute
operands. In particular, `rm -rf /*` prompts rather than being silently denied;
the later temp-descendant patterns are the narrow allowed exceptions. Secret-path
deletion rules remain later still and therefore continue to prompt. Later
current/parent-segment and common multi-operand rules keep forms such as
`/tmp/..`, `/tmp/./../child`, redundant-slash root aliases such as `/tmp//`,
`cache /etc`, and `cache ../child` prompt-gated. This is deliberately
conservative but still cannot prove arbitrary shell syntax: quoting, variable
and wildcard expansion, command substitution, unusual option placement, and
symlink resolution remain outside what static command globs can establish.

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

The root TUI is patched to gather pending permission and question requests from
the complete descendant session tree. Upstream 1.18.18 only gathers the root and
direct children, which leaves grandchild prompts invisible and stalls nested
agent chains. See [OpenCode patch lifecycle](opencode-patches.md) for the active
patch inventory, validation workflow, upstream references, and explicit removal
criteria (including the separate verified OpenCode v2 migration condition).

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

The module locally overrides the already-evaluated node-modules derivation to
avoid recursively copying the completed dependency tree. Patching
`nix/node_modules.nix` through `patchedOpencode` cannot affect it because that
file is excluded from the package source fileset. The override injects setup
that copies the much smaller source tree to `$out` and runs the inherited
upstream build phase there; a unique-marker assertion makes upstream phase drift
fail evaluation instead of duplicating and potentially missing changed Bun flags
or canonicalization steps. The cleanup install phase removes non-module source
files while preserving workspace parent directories, dependency symlinks,
executable modes, and the fixed-output hash. Bake and benchmark this local
override before translating it into an upstream source change, and remove it
once an equivalent output-verified implementation is pinned. See the patch
lifecycle document for the fixture and exact removal criterion.

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

The runtime note also appends a concise Nix usage rule telling agents to prefer
`nix build .#x` + `./result/bin/x` over repeated `nix run .#x` and to treat
`SQLite database is busy` as a harmless retry warning. This keeps parallel
agents from serializing on the nix store database; see
[suremac](/docs/suremac.md) for the daemon-side tuning.

Use `agentSupportPackages` for dependencies that a visible tool needs under the
hood but that the agent does not need to call directly.

## direnv environments for agent commands

`dotfiles.opencode.direnv.enable` (default: `programs.direnv.enable`) installs
the `dotfiles-direnv` OpenCode plugin at
`~/.config/opencode/plugins/dotfiles-direnv.js`. OpenCode triggers the
`shell.env` plugin hook with the working directory of every bash tool
invocation, and the plugin merges the output of `direnv export json` for that
directory into the command environment.

This means agents get project dev-shell tooling (via nix-direnv) transparently,
including subagents dispatched across repos with `workdir` outside the session
root. They should run project commands directly (`just test`, `cargo build`)
rather than wrapping them in `nix develop --command` or `direnv exec`; the
wrappers are slower and also defeat bash permission matching on the underlying
command. The runtime note tells agents this when the plugin is enabled.

Behavior details:

- The nearest `.envrc` is found by walking up from the command's cwd, stopping
  at the home directory. Only direnv-allowed files load; blocked or failing
  `.envrc`s are skipped silently and negative-cached for one minute, so a repo
  becomes available shortly after an interactive `direnv allow`.
- Results are cached per `.envrc` root with a five-minute TTL plus an mtime
  fingerprint over `.envrc`, `flake.nix`, `flake.lock`, and similar files.
  Warm nix-direnv evaluations take tens of milliseconds; the first load of a
  cold dev shell pays full flake evaluation (bounded by a ten-minute timeout),
  so warming big shells interactively first helps.
- If OpenCode itself was launched inside a direnv environment, commands running
  in directories without an `.envrc` receive the unload diff so the launch
  repo's dev shell does not leak into other projects.
- direnv reports unset variables as nulls; the hook can only merge over
  OpenCode's process environment, so those become empty strings.

The plugin substitutes the host's `programs.direnv.package` binary path at
build time and shares the user's direnv allow database and nix-direnv cache
with interactive shells.

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

- `code-review`, for ordinary behavioral review of a named change. It judges
  stated intent and reachable behavior, distinct from `interrogate-me`
  adversarial review, `blast-radius` compatibility analysis, `how` architecture
  critique, and forge or PR workflows
- `how`, for architecture and runtime explanations, and `why`, for
  evidence-backed investigations of intent and history
- `teach`, for paced explanations that build a mental model from mechanics and,
  when needed, rationale
- `recall`, for reconstructing current work state from live artifacts and bounded
  ctx history
- `reflect`, for evidence-backed lessons and proposed process or tooling
  improvements; it waits for approval before applying anything
- `interrogate-me`, for independent adversarial reviews routed through the
  shared `subagent-selection` policy; it returns a lead verdict without fixes
- `blast-radius`, for tracing compatibility and downstream breakage beyond a
  diff, then testing the assumptions that make the change safe
- `technical-writing`, for substantive engineering artifacts such as READMEs,
  tutorials, RFCs, and design docs; it adds document structure and technical
  accuracy while `impactful-writing` remains the general prose filter
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
- `rust-cargo` (registered by the OpenCode module through the shared skill
  registry; `dotfiles.devCache` appends host-specific sccache guidance so
  agents keep cargo output concise and never clear `RUSTC_WRAPPER`)
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
