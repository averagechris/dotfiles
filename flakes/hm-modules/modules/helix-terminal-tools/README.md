# Helix terminal tools for WezTerm

This Home Manager module integrates terminal tooling with the Helix editor through WezTerm panes:

1. A Yazi file picker that opens beside Helix, so you can browse and open files without leaving the editor
2. A Claude Code bridge that pipes selections, functions, and diagnostics from Helix to a Claude pane with file, line, and column metadata

Both integrations drive one Rust binary named `helix-terminal-tools`.

## Requirements

- Helix installed through `programs.helix`, so the module can merge keybindings into your settings
- [WezTerm](https://wezfurlong.org/wezterm/), which provides all pane management
- For the file picker: Yazi installed through `programs.yazi`, so the module can generate a matching config
- For the AI bridge: a `claude-code` CLI (`claudePackage` defaults to `pkgs.claude-code`)

## Enable it

```nix
{
  dotfiles.helix-terminal-tools = {
    enable = true;
    yazi.enable = true;
    claude.enable = true;
  };
}
```

The hm-modules flake exports this module as `homeManagerModules.helixTerminalTools`. Enabling the module installs the `helix-terminal-tools` binary; each integration only takes effect when its own `enable` is set.

## Options

All options live under `dotfiles.helix-terminal-tools`.

| Option | Type | Default | Purpose |
|--------|------|---------|---------|
| `enable` | bool | `false` | Install the binary and apply integrations |
| `package` | package | built from this directory | The `helix-terminal-tools` derivation |
| `wezterm` | package | `pkgs.wezterm` | WezTerm used for every pane command |
| `claudePackage` | package | `pkgs.claude-code` | Claude CLI launched by the AI bridge |
| `yazi.enable` | bool | `false` | File picker integration |
| `yazi.package` | package | `pkgs.yazi` | Yazi launched in the picker pane |
| `yazi.pickerWidth` | int | `30` | Picker pane width as a percentage |
| `yazi.pickerSide` | `"left"` or `"right"` | `"left"` | Side of the screen for the picker pane |
| `yazi.helixKeybinding` | string | `"space.t.f"` | Documented for future use; the binding is currently hardcoded to `space.t.f` |
| `claude.enable` | bool | `false` | Claude Code integration |

Changing `yazi.pickerWidth` or `yazi.pickerSide` rewrites the `space.t.f` command with the new values. Changing `yazi.helixKeybinding` does nothing today because the module writes the `space.t.f` binding literally.

## Keybindings

### File picker

| Keys | Action |
|------|--------|
| `Space t f` | Toggle the Yazi picker pane on the configured side |
| `q` inside Yazi | Quit and return focus to Helix |

Opening an entry in Yazi runs the generated `edit` opener, which sends the file to Helix and leaves the picker open for more browsing. Your normal Yazi keybindings and theme carry over because the generated config starts from your `programs.yazi` settings.

### Claude Code bridge

All chords start with `Space c` in normal mode. Each one pipes the current selection to `send-to-claude-ai`, which forwards it to a running Claude pane or launches `claude-code`.

| Keys | Action |
|------|--------|
| `Space c c` | Save the buffer, then ask Claude to implement any TODO/FIXME comments in the selection, or suggest refactoring improvements |
| `Space c C` | Same request without saving; the header notes the buffer may be unsaved |
| `Space c e` | Save the buffer, then ask Claude to explain the selection from the saved file |
| `Space c E` | Ask Claude to explain the selection from the unsaved editor buffer |
| `Space c f` | Jump to the next function, select it, and send it to Claude |
| `Space c t` | Send the next function with a request to generate comprehensive tests |
| `Space c d` | Send the next function with a request to add or improve documentation and docstrings |
| `Space c x` | Save the buffer, then send the selection as error context and ask Claude to fix the diagnostics |
| `Space c u` | Select the inner textobject and ask Claude for usage examples |
| `Space c o` | Save the buffer, then ask Claude to optimize the selection for performance and readability |

Every chord passes the buffer name and cursor line; the selection-based chords (`c`, `C`, `e`, `E`, `x`, `o`) also pass the cursor column. Each chord sets a content type of `selection`, `function`, or `error`.

### WezTerm pane management

| Keys | Action |
|------|--------|
| `Space g g` or `Space o g` | Split a top pane running `git ui` |
| `Space o h` / `Space o v` / `Space o t` | Split a bottom or right shell pane |
| `Space o T` | Spawn a new WezTerm window |
| `Space o tab` | Spawn a new WezTerm tab |
| `Space k f` | Toggle pane zoom |
| `Space k m/n/e/i` | Move focus to the left, down, up, or right pane |

## Command-line interface

```
helix-terminal-tools open-picker [--dir PATH] [--width PERCENT] [--side left|right]
helix-terminal-tools open-file PATH
helix-terminal-tools send-to-claude-ai [--file NAME] [--line N] [--column N]
                                       [--content-type TYPE] [--saved] [--header TEXT]
                                       [--syntax LANG] [--no-metadata] [--snippet]
```

Global flags: `-v`/`--verbose` for debug logging, plus `--wezterm-path`, `--yazi-path`, `--yazi-config-dir`, and `--claude-path`. When you invoke the binary by hand, `open-picker` defaults to 40 percent width on the left; the Helix binding always passes your configured values instead.

## How it works

- **Picker toggle.** `open-picker` looks for a pane in the configured direction within the current tab. If that pane runs Yazi, it refocuses Helix and closes it. Otherwise it replaces any non-Yazi pane in that direction and splits a new pane running Yazi with `HELIX_PANE_ID` and `YAZI_CONFIG_HOME` set.
- **Generated Yazi config.** The module writes `~/.config/helix-terminal-tools/yazi/` containing `yazi.toml` (your settings plus the `edit` opener calling `open-file`), `keymap.toml` (your keymap with the `q` quit binding prepended so it wins), and `theme.toml`.
- **Opening files.** `open-file` resolves the Helix pane from `HELIX_PANE_ID`, falling back to a pane whose title contains `hx`, activates it, and sends `:open <path>` with the absolute path. The Yazi pane stays open.
- **Claude delivery.** `send-to-claude-ai` reads the piped text from stdin, wraps it with a JSON metadata block (tool name, timestamp, hostname, file type and language detection, cursor position), and formats recognized languages in a fenced code block. It sends the message to an existing pane whose title contains `claude`, or launches the `claude-code` binary with the message when no pane exists.

## License

MIT.
