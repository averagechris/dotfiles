# Anyrun Launcher

Anyrun is the primary application launcher for Hyprland. It provides fast app search, command execution, a calculator, and symbol/emoji lookup with a compact, Raycast-style UI.

## Usage

- **Open launcher**: `Super+Space`
- **Search apps**: type the app name
- **Run commands**: prefix with `>` (shell plugin)
- **Calculator**: type expressions (rink plugin)
- **Symbols/emoji**: type keywords (symbols plugin)

When the launcher opens with an empty input, the input field displays a subtle hint so the window never looks blank.

## Configuration

Enable the module with:

```nix
dotfiles.anyrun.enable = true;
```

The anyrun flake input must be available to the host flake:

```nix
anyrun.url = "github:anyrun-org/anyrun";
```

Since anyrun 25.12.0, the `anyrun-provider` binary is required. This module installs it so the binary is available in your PATH.

## Daemon

Anyrun uses a small daemon to handle launch requests over D-Bus. If a non-daemon anyrun instance is already running, new launches can fail with a D-Bus interface error. This configuration starts the daemon once when Hyprland launches so the runner is always available:

```
anyrun daemon
```

## Desktop entries

The applications plugin reads desktop files from `XDG_DATA_DIRS`. This configuration sets:

```
XDG_DATA_DIRS=${config.home.profileDirectory}/share:/nix/var/nix/profiles/default/share
```

so Anyrun can see your installed applications in `/etc/profiles/per-user/<user>/share/applications`.

## Plugins

The current plugin set is:

- **applications**: app and desktop entry search
- **shell**: command execution
- **rink**: calculator
- **symbols**: emoji and symbol search

## Appearance

The launcher is a floating window (not fullscreen) with a transparent outer layer and a compact main card. Size and placement are tuned to be centered near the top of the screen:

- `width.fraction = 0.35`
- `height.absolute = 280`
- `y.fraction = 0.18`

Theme colors come from the Hyprland theme module (`dotfiles.gui.hyprland.theme`).

## Customization

Edit the module at `flakes/hm-modules/modules/gui/anyrun/default.nix` to:

- adjust size/placement
- add or remove plugins
- tweak CSS for the window, input, and results
- add plugin-specific settings in `extraConfigFiles.*.ron`
