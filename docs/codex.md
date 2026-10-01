# Codex

The Home Manager module at `flakes/hm-modules/modules/codex/` wraps the pinned
upstream `programs.codex` module. It is exported as
`homeManagerModules.codex`, imported by the default module, and enabled on
`suremac`. It configures the existing desktop installation without installing a
second CLI or changing model and permission defaults.

```nix
dotfiles.codex = {
  enable = true;
  # Optional CLI installation on hosts without the desktop app:
  # package = pkgs.codex;
  settings = {
    # Declare only defaults you want enforced at Home Manager activation:
    # model_reasoning_effort = "medium";
  };
  extraInstructions = "Use this host's repository setup instructions.";
};
```

## Shared guidance and skills

`modules/agent-guidance.md` supplies shared autonomy, brevity, verification,
review, and design judgment guidance to Codex and the OpenCode orchestrator.
Codex adds its own instructions for native subagents, Git worktrees, built-in
tools, and explicit dev-shell setup. It does not impose jj globally. Repository
VCS instructions still apply, and spawned subagents do not automatically have
isolated checkouts.

`modules/agent-workflows.nix` registers seven portable skills independently of
OpenCode: conventional-commits, test-curation, teach, project-map,
impactful-writing, technical-writing, and rust-cargo. Their existing source
directories remain under `modules/opencode/skills/`; both clients consume the
same rendered sources. The registry retains strict patches, additive host
instructions, full companion directories, and bundle audits.

Every registry entry has a `targets` list. Existing registrations default to
`["opencode"]`; portable registrations default to `["opencode" "codex"]`.
Each client receives its targets only while `programs.<client>.enable` is true.
Codex skills deploy to `~/.agents/skills/<name>` using the current documented
personal skill directory. OpenCode skills retain their existing XDG paths.
Unmanaged skills can coexist. For example:

```nix
dotfiles.agentSkills.rust-cargo.targets = ["codex"];
dotfiles.agentSkills.teach.enable = false;
```

The initial set excludes workflows coupled to OpenCode's named agent roster,
Bay/jj workspace management, and ctx history assumptions. These need explicit
adaptation before opting into Codex. Host CLI skills remain OpenCode-only unless
a host adds Codex to their targets. Private skill appendices are not migrated;
never place decrypted material in Nix settings, prompt strings, or sources.

## Writable configuration

Upstream `programs.codex.context` manages `AGENTS.md`. The desktop app retains
ownership of browser runtime paths, installed plugins, notification settings,
UI preferences, credentials, history, and worktrees. Home Manager does not link
`config.toml` into the immutable store.

`dotfiles.codex.settings` overlays declared leaf values into that writable TOML
file after linking the generation. Unrelated keys and comments survive.
Activation records only the declared values in
`dotfiles-managed-settings.json`. Removing a declaration removes its old value
only if it is still unchanged locally; app or user edits to removed values are
preserved. Current declarations win on the next activation. An empty initial
settings set does not touch the config file.

The first nonempty merge retains `config.toml.before-dotfiles` for recovery.
Malformed TOML/ownership data or an existing config symlink fails before writes.
Writes use atomic replacement and user-only permissions. Stop the app during
activation when changing settings to avoid concurrent config writes. Disabling
the module removes Home Manager links but leaves writable settings/history;
activate with `settings = {}` first to release previously managed keys.

Use `dotfiles.codex.settings.mcp_servers` for explicit additional MCP servers.
Do not mix this mode with upstream settings/plugin/marketplace config writers
or shared MCP integration; the module rejects those combinations. Native
profiles, rules, and hooks remain available through `programs.codex`. Keep
secrets in their runtime credential stores.

## Environment and activation

Desktop sessions are not assumed to inherit the interactive shell's direnv
state. Codex guidance asks agents to use repository/local-environment setup or
`direnv exec <workdir> <command>` for an already allowed environment. This module
does not port OpenCode's per-command direnv or Rust environment hooks.

Build and review before switching:

```sh
nix flake check ./flakes/hm-modules
nh darwin build -q --no-nom . --hostname suremac
```

The module is not activated by editing these files. After switching, start a new
Codex chat to pick up global guidance. Existing local config is preserved.

## Community patterns

- [Home Manager Codex module](https://nix-community.github.io/home-manager/options/home-manager/programs/codex.html)
  already supplies nullable package installation, context, skills, profiles,
  rules, hooks, and plugin management. This wrapper reuses those options while
  preserving this desktop app's writable config.
- [agent-skills-nix](https://github.com/Kyure-A/agent-skills-nix) uses a shared
  source catalog and per-client deployment targets. The existing dotfiles
  registry already provides rendering and source audits, so no additional flake
  dependency is needed.
- [nix-agent-wire](https://github.com/srid/nix-agent-wire) demonstrates shared
  guidance and resource directories, but its documented targets are OpenCode
  and Claude Code, not Codex.
- [Codex skill discovery](https://learn.chatgpt.com/docs/build-skills#where-codex-loads-local-skills)
  documents `~/.agents/skills` and symlink support. The upstream Home Manager
  skills option currently uses `CODEX_HOME/skills`; this registry uses the
  documented shared personal directory directly.
