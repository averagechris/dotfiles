# Pi

This repository packages the [Pi coding agent](https://pi.dev/) and exposes a
Home Manager module for installing and configuring it.

## Package

The `pkgs.pi` and `pkgs.pi-coding-agent` attributes come from the shared
`base-lib` overlay. They install Pi's upstream native release archive for the
current platform rather than building from npm source.

The package is pinned to a specific upstream version and hash in
`flakes/base-lib/packages/pi-coding-agent.nix`.

Pi is intentionally **not** a flake input right now. The goal is to make Pi
updates explicit and reviewable instead of letting routine flake updates advance
a fast-moving coding agent automatically. This is especially important because
Pi is distributed through the npm ecosystem upstream, even though this package
uses the native release archive rather than resolving npm dependencies during a
Nix build.

Tradeoffs of the current approach:

- Updates change `flakes/base-lib/packages/pi-coding-agent.nix` explicitly rather
  than advancing a flake input.
- Routine `update-flakes` runs apply the same cooldown gate used for
  fast-moving agent inputs before updating Pi's pinned archives.
- The review diff for an update is small and obvious: version plus platform
  hashes.
- Building does not run npm, Bun, or dependency lifecycle scripts.
- Local patches or a long-lived fork would be awkward; if we start patching Pi,
  reconsider using a flake input or forked source checkout.

Prefer keeping Pi manually pinned until there is a concrete need to consume Pi
source directly, apply patches, or track a fork. If Pi becomes a flake input in
the future, include it in the update cooldown list and pin it to an explicit tag
or revision rather than an unreviewed moving branch.

## Updating Pi

Before bumping Pi:

1. Wait at least the same cooldown window used for fast-moving agent inputs
   (currently 7 days by default in `update-flakes`).
2. Review the upstream release notes and recent issues for the target release.
3. Prefer a released version over an arbitrary branch commit.
4. Prefer the manifest-driven updater so all platform hashes are refreshed
   together:

   ```bash
   update-flakes --manual-packages-only --manual-package pi-coding-agent
   ```

   If updating by hand, update `version` and the platform hashes in
   `flakes/base-lib/packages/pi-coding-agent.nix`.
5. Build the package and verify `pi --version`.
6. Run the relevant Home Manager/module checks before committing.

Useful validation commands:

```bash
nix build --impure --expr 'let flake = builtins.getFlake "path:/Users/chris/dotfiles/flakes/base-lib"; system = builtins.currentSystem; pkgs = import flake.inputs.nixpkgs { inherit system; overlays = [ flake.overlays.default ]; config.allowUnfree = true; }; in pkgs.pi' --no-link
nix flake check ./flakes/hm-modules
```

## Home Manager

Enable Pi with:

```nix
programs.pi.enable = true;
```

The module installs `pkgs.pi`, writes `~/.pi/agent/settings.json`, and can manage
optional resource paths, custom model configuration, shell environment variables,
and wrapper commands.

Default settings are intentionally opinionated for this dotfiles repo:

```json
{
  "defaultProvider": "openrouter",
  "defaultModel": "openai/gpt-5.5",
  "defaultThinkingLevel": "low",
  "quietStartup": true,
  "collapseChangelog": true,
  "enableInstallTelemetry": false,
  "enabledModels": [
    "anthropic/*opus*",
    "anthropic/*sonnet*",
    "anthropic/*haiku*",
    "openai/gpt-*",
    "moonshotai/*kimi*",
    "google/gemini*"
  ]
}
```

Override or extend those settings with `programs.pi.settings`; the module merges
your values over the defaults:

```nix
programs.pi = {
  enable = true;
  settings = {
    defaultThinkingLevel = "medium";
    compaction = {
      enabled = true;
      reserveTokens = 16384;
      keepRecentTokens = 20000;
    };
  };
};
```

### Credentials

Use `openrouterApiKeyFile` to hook Pi up to the shared OpenRouter agenix secret:

```nix
programs.pi = {
  enable = true;
  openrouterApiKeyFile = config.age.secrets.openrouter-api-key.path;
};
```

By default the module configures the key in two places:

- `~/.pi/agent/auth.json` gets an OpenRouter `api_key` entry whose key is a
  shell command, e.g. `!/nix/store/.../bin/cat /run/agenix/openrouter-api-key`.
  The secret value is not copied into the Nix store. This makes Pi's OpenRouter
  model catalog available even before a shell startup file has exported the
  environment variable, avoiding warnings from `enabledModels`.
- shell initialization exports `OPENROUTER_API_KEY` for Pi subprocesses,
  extensions, and ad-hoc CLI usage. This mirrors the OpenCode module.

Set `programs.pi.exportOpenrouterEnv = false` if a host should manage Pi auth
without exporting the key to the shell. Set
`programs.pi.manageOpenrouterAuthFile = false` if Pi should manage `auth.json`
itself with `/login` or additional provider credentials.

The module also exports these environment variables by default:

```bash
PI_SKIP_VERSION_CHECK=1
PI_TELEMETRY=0
```

Because Nix manages the installed Pi package, upstream self-update prompts and
install telemetry are not useful in normal dotfiles-managed sessions. Add or
override variables with `programs.pi.environment`.

### Resources and custom models

Pi can load declarative packages, extensions, skills, prompt templates, and
themes from settings. Use the dedicated options instead of hand-editing
`settings.json`:

```nix
programs.pi = {
  packages = [
    # "npm:some-pi-package@1.0.0"
    # "git:github.com/user/repo@v1"
  ];

  extensions = [./pi/extensions/safety.ts];
  skills = [./pi/skills];
  prompts = [./pi/prompts];
  themes = [./pi/themes];
};
```

If a provider/model needs custom catalog metadata or routing overrides, set
`programs.pi.models`. Non-empty values write `~/.pi/agent/models.json`:

```nix
programs.pi.models = {
  providers.openrouter.modelOverrides."openai/gpt-5.5" = {
    reasoning = true;
    input = ["text" "image"];
  };
};
```

Leave `models = {}` to avoid managing `models.json`.

### Wrapper commands

Define named wrapper commands for common modes. Wrapper arguments are fixed by
Nix and user-provided arguments are appended at runtime:

```nix
programs.pi.wrappers = {
  readonly.tools = ["read" "grep" "find" "ls"];

  deep = {
    model = "openrouter/anthropic/claude-opus-4.5";
    thinking = "high";
  };

  plan = {
    tools = ["read" "grep" "find" "ls" "bash"];
    appendSystemPrompts = [''
      Work in planning mode. Do not edit files unless explicitly asked.
      Produce concrete implementation steps and risks.
    ''];
  };
};
```

Those examples install `pi-readonly`, `pi-deep`, and `pi-plan`.

To override the installed package:

```nix
programs.pi = {
  enable = true;
  package = pkgs.pi;
};
```

## Runtime state

Pi stores global settings, credentials, sessions, and installed Pi packages
under `~/.pi/agent/`. This module manages `settings.json`, optionally manages
`models.json`, and manages `auth.json` only when `openrouterApiKeyFile` and
`manageOpenrouterAuthFile` are both enabled. It intentionally does not manage
sessions, npm/git package checkouts, or other mutable runtime state.
