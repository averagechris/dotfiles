# Shell configuration

## Zsh module

The Home Manager Zsh module lives at `flakes/hm-modules/modules/shell-modules/zsh.nix`.
It enables the Zsh configuration used across hosts, including aliases, history
settings, and environment setup.

### PATH precedence

The Zsh config prepends `~/.nix-profile/bin` to `PATH` so profile overrides take
priority over Home Manager `home.packages`. This makes it easy to temporarily
install newer versions in a profile and have them win by default.

```
export PATH="$HOME/.nix-profile/bin:$PATH"
```

## direnv

The shell module enables direnv and nix-direnv by default for project-local dev
shells. Direnv runs in silent mode by default (`programs.direnv.silent = true`)
so entering a flake-backed project does not print the full environment diff such
as `direnv: export +AR +CC ... ~PATH` on every shell activation.

When OpenCode is enabled, the OpenCode module also ships a `dotfiles-direnv`
plugin that applies each project's direnv environment to agent shell commands
per working directory; see [OpenCode](/docs/opencode.md#direnv-environments-for-agent-commands).

## Zellij

Zellij is installed and configured by the shell module but is **disabled by
default**. To enable it on a host, set:

```nix
programs.zellij.enable = true;
```

The module deploys `~/.config/zellij/config.kdl`, layouts, and themes only when
Zellij is enabled.

## `calibre-utils`

`dotfiles.shell.calibre-utils.enable` installs the `calibre-utils` helper CLI.
By default it keeps only the audiobook-oriented helpers and their lighter runtime
dependencies, such as Python, Rich/Typer/Tabulate, and FFmpeg.

The `backup` subcommand, which exports a Calibre library and can upload the
archive with MEGAcmd, is optional because it retains the full Calibre and MEGAcmd
closures. Enable it only on hosts that actually perform Calibre library backups:

```nix
dotfiles.shell.calibre-utils.backup.enable = true;
```

When backup support is disabled, `calibre-utils backup` remains present as a stub
that explains how to enable the heavy optional dependency set.
