# Codex

The Home Manager module at `flakes/hm-modules/modules/codex/` wraps the pinned
upstream `programs.codex` module. It is exported as
`homeManagerModules.codex`, imported by the default module, and enabled on
`suremac`. It configures the existing desktop installation without installing a
second CLI. The suremac host declares `model = "gpt-6.1-sol"` and
`model_reasoning_effort = "low"` through `dotfiles.codex.settings`; permission
defaults remain unchanged.

```nix
dotfiles.codex = {
  enable = true;
  # Optional CLI installation on hosts without the desktop app:
  # package = pkgs.codex;
  settings = {
    # Declare only defaults you want enforced at Home Manager activation:
    # model_reasoning_effort = "medium";
  };
  # extraInstructions = "<additional host-specific guidance>";
};
```

## Shared guidance and skills

`modules/agent-guidance.md` supplies concise explanations, smaller changes,
behavioral checks, and design judgment to Codex and the OpenCode orchestrator.
Codex adds model-selection guidance and a command for loading direnv project
environments in desktop sessions.
Home Manager combines these files and `extraInstructions` into the global
`AGENTS.md`. The shared skills carry topic-specific workflows and use the same
sources in both clients. Their detailed teaching, writing, testing, and discovery
guidance is retained. The teaching workflow assumes `how` and `why` are available. Project discovery
uses optional helper skills when available.

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
Codex links each complete skill directory into `~/.agents/skills`
(`recursive = false`). In ChatGPT desktop 26.928.40906, a directory-level
symlink made an otherwise identical skill appear in the Skills picker;
Home Manager's recursive file-level symlinks did not. OpenCode retains its
existing recursive deployment, and both clients use the same rendered contents.

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

## Model selection and outside feedback

The global guidance prioritizes budget efficiency. Sol at high reasoning chooses
approaches and plans, then delegates clear implementation tasks to Luna. Routine
work can start with Luna. Astra is reserved for consequential uncertainty that
Sol at high reasoning cannot resolve.

For occasional outside-model feedback, agents can use
`opencode run --model <provider/model#variant>`. Rare Wise-level consultations
favor Fable 5.1 or Opus 5.5 for taste judgments about coherence, simplicity,
wording, and user experience. The example uses
`openrouter/anthropic/claude-fable-5.1#high` with a compact decision packet and
analysis-only instructions. Sol retains planning and Luna handles clear
implementation tasks. The documented example
uses `--standalone` for a private server and `--file` to attach the packet.
These calls use the host's OpenCode provider credentials and billing.

Routing guidance is distinct from fallback defaults. The suremac TOML defaults
are Sol 6.1 with low reasoning after activation. Explicit task model and reasoning
selections implement the routing policy and take priority over fallback values.

The official [configuration documentation](https://learn.chatgpt.com/docs/config-file/config-basic)
documents user TOML defaults for the CLI and IDE, with higher-priority overrides.
It does not establish that these defaults replace the desktop's saved selections
when grem launches a task with omitted selections. Those launches use saved
desktop defaults. Verify a fresh launch before claiming the live desktop fallback
matches the Nix declaration. Do not rewrite opaque desktop state to force it.

Editing Nix does not activate settings. A full Darwin activation may apply other
pending changes, so review the complete activation separately. A PR alone does
not change the live TOML or desktop picker. The OpenCode CLI syntax was checked with the
installed `opencode run --help`; no paid model call was needed for validation.

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

The Codex guidance uses `direnv exec <workdir> <command>` to load project
environments for shell commands in desktop sessions. The Rust skill documents
the host's compiler cache and service recovery commands.

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


## Michi on Thorny

Michi's owner DM uses the pinned Codex CLI through a queued `michi-codex`
command. This is a service-user installation with its own ChatGPT login and
owner workspace, independent of the workstation's Home Manager configuration.
`flakes/hosts/thorny/personal-codex.nix` reuses the shared skill registry and
renderer for this service account. NixOS links complete skill directories into
its `~/.agents/skills` directory: the seven portable skills, `how`, `why`,
`memo`, `rdny-browser`, and the three SourceHut skills. Its instructions retain
Thorny's Codex model and sub-agent guidance. The `how` and `why` helpers use
Codex delegation and omit work-specific source playbooks.
The owner shell, queued worker, and remote Codex server receive the personal
`memo`, `srht`, and `showboat` CLIs alongside the existing coding and browser
tools. History remains available through `michi-codex-sessions`.
Codex is encouraged to use `memo` quietly and selectively for durable project
learnings and decision history. Memo is an append-only note history with an
aligned summary tree. `wake` covers the whole selected history within its line
budget, not keyword search results. When `wake` or `note` requests a summary,
the agent summarizes the two supplied sources and submits the result with the
printed, store-pinned `nap` command. Repeat an incomplete wake until complete.
Memo makes no model calls; bare `nap` prints the next eligible request.
Notes are single lines of at most 280 UTF-8 bytes;
correct an old note by appending one that identifies what it supersedes.

Run memo from a project repository to use its project store; worktrees share
that store. Keep `--data-dir <owner workspace>/memo` explicit. Use the `default`
store only for cross-project preferences and Michi's personal context. Memo
does not combine project and default stores into one wake. Check each separately
when both are relevant. Routine reads, notes, and maintenance stay quiet, with
no usage reports or reminders. Notes are leads to verify against current code.

This profile excludes Linear, Datadog, Sentry, AWS/Kubernetes tools, work meeting
integrations, and private Sure stack context. SourceHut authentication must be
configured for the service account separately; workstation credentials are not
copied. No Codex config, plugins, or login files are replaced.
NixOS activation applies these links and service PATH changes; editing the
module alone does not update a running Codex session.
See [the ZeroClaw runbook](zeroclaw.md#codex-coding-jobs) for login, execution,
job results, and the worker's isolation from other chats.
