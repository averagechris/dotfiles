# Shell configuration module

This module provides the shell environment, including terminal tools, CLI utilities, and shell integrations.

## Features

- **Shell Integration**: Zsh with Oh-My-Zsh, Zellij terminal multiplexer, and Starship prompt
- **Development Tools**: Git, Lazygit, Gitui, Jujutsu VCS, and pre-commit hooks
- **File Management**: Yazi file manager, Ranger, and FZF fuzzy finder
- **Editor Integration**: Helix and Neovim with custom configurations
- **System Utilities**: Ripgrep, silent direnv/nix-direnv, htop, and custom shell scripts
- **Python Support**: Optional Python interpreter with ipython
- **Clipboard Integration**: Platform-aware copy/paste commands (wl-clipboard on Linux, pbcopy/pbpaste on macOS)

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `true` | Enable the shell configuration |
| `python.enable` | bool | `false` | Install Python interpreter with optional packages |
| `yazi.enable` | bool | `false` | Enable Yazi terminal file manager |
| `gpg.enable` | bool | `true` | Set up GPG_TTY environment variable |
| `shell_scripts.enable` | bool | `true` | Enable custom shell scripts |
| `env.editor` | enum | `"hx"` or `"nvim"` | Default editor (hx if Helix enabled, else nvim) |
| `commands.copy` | string | Platform-dependent | Command for clipboard copy |
| `commands.paste` | string | Platform-dependent | Command for clipboard paste |

## Usage

Enable the shell module in your Home Manager configuration:

```nix
{
  dotfiles.shell = {
    enable = true;
    python.enable = true;
    yazi.enable = true;
    env.editor = "hx";
  };
}
```

## Included sub-modules

- **zsh**: Shell configuration with Oh-My-Zsh
- **zellij**: Terminal multiplexer
- **git**: Git configuration
- **gitui**: Git UI tool
- **neovim**: Neovim editor
- **jujutsu**: Jujutsu version control
- **fzf**: Fuzzy finder
- **lazygit**: Git UI
- **yazi**: Terminal file manager
- **ranger**: File browser
- **less**: Pager configuration
- **pipx**: Python package manager
- **calibre-utils**: Calibre utilities

## Default packages

When enabled, the module installs:
- curl, fd, just, procs, titlecase
- Additional shell scripts (if `shell_scripts.enable = true`)

## Environment variables

- `EDITOR`: Set to configured editor (hx or nvim)
- `GIT_EDITOR`: Set to configured editor
- `GPG_TTY`: Set to current TTY (if gpg.enable = true)
