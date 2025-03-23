# Helix-Yazi Integration for WezTerm

This integration enables a seamless workflow between the Helix editor and Yazi file manager within WezTerm, creating an IDE-like experience.

## Features

- Open Yazi file manager in a side pane directly from Helix
- Toggle file picker on/off with the same keybinding
- Select files in Yazi to open them in Helix (without closing Yazi)
- Keeps track of panes within the current tab
- Automatically close Yazi pane when quitting with `q`
- Configurable side and width for the file picker
- Preserves your existing Yazi configuration (themes, keybindings, etc.)

## Requirements

- [Helix](https://helix-editor.com/) editor
- [Yazi](https://yazi-rs.github.io/) file manager
- [WezTerm](https://wezfurlong.org/wezterm/) terminal

## Installation

This integration is designed as a Home Manager module. Add it to your Home Manager configuration:

```nix
{
  dotfiles.helix-yazi-integration = {
    enable = true;
    # Optional: Customize settings
    pickerWidth = 30;  # Width of file picker as percentage
    pickerSide = "left";  # "left" or "right"
    helixKeybinding = "space.e";  # Helix keybinding to open picker
  };
}
```

## Usage

1. In Helix, press your configured keybinding (default: `Space` + `t` + `f`) to open the Yazi file picker
2. Navigate the file tree with Yazi's controls (all your regular Yazi keybindings work!)
3. Press `Enter` on a file to open it in Helix (Yazi stays open for more browsing)
4. Press `q` to close Yazi and return to Helix
5. Press `Space` + `t` + `f` again to toggle the file picker off

## Command-line Interface

The integration provides a CLI with the following commands:

```
# Open the file picker from Helix
helix-yazi-integration open-picker [--dir PATH] [--width PERCENT] [--side left|right]

# Open a file in Helix from Yazi
helix-yazi-integration open-file PATH

# Install the integration (typically handled by Home Manager)
helix-yazi-integration install
```

## Configuration

### Home Manager Options

| Option | Description | Default |
|--------|-------------|---------|
| `enable` | Enable the integration | `false` |
| `package` | Custom package derivation | Default build |
| `wezterm` | WezTerm package | `pkgs.wezterm` |
| `yazi` | Yazi package | `pkgs.yazi` |
| `pickerWidth` | Width of file picker (%) | `30` |
| `pickerSide` | Side to show picker | `"left"` |
| `helixKeybinding` | Helix keybinding (Note: currently hardcoded to space.t.f) | `"space.t.f"` |

## How It Works

The integration manages communication between Helix, Yazi, and WezTerm:

1. When triggered from Helix, it opens Yazi in a side pane using WezTerm's pane management
2. If the file picker is already open, it closes it (toggle behavior)
3. It passes environment variables like `HELIX_PANE_ID` and `YAZI_CONFIG_HOME` to Yazi
4. The integration uses a custom Yazi config that inherits all your normal settings and keybindings
5. When a file is selected in Yazi, it finds the Helix pane (using the saved pane ID) and sends commands to open the file
6. The Yazi pane stays open so you can browse and open multiple files
7. When quitting Yazi with `q`, the pane automatically closes
8. The integration intelligently searches for Helix panes within the current tab if the environment variable is not available

## Possible Future Enhancements

Here are some ideas for future improvements to the integration:

1. **Customizable Keybindings**: Make the Helix keybinding fully configurable (currently hardcoded to `space.t.f`)
2. **Additional Configuration Options**:
   - Custom Yazi quit key
   - Tabs vs. panes preference
   - Ability to customize environment variables passed to Yazi
3. **Enhanced Path Handling**: More robust handling of paths with special characters and spaces
4. **Testing Infrastructure**: Add unit tests for pane detection logic and command handling
5. **Multiple File Selection**: Support for selecting multiple files in Yazi and opening them in Helix tabs
6. **Session Persistence**: Remember open file browser state between Helix sessions
7. **Advanced Layout Management**: Support for more complex layouts (vertical splits, etc.)
8. **Improved Error Messages**: More user-friendly error messages for common issues

Contributions to any of these enhancements are welcome!

## License

MIT