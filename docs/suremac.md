# suremac macOS Configuration

`suremac` is the Darwin/macOS host configured in `flakes/hosts/suremac/`.

## Spaces / Desktops

Mission Control desktop switching is configured with stable Space ordering:

- `system.defaults.dock.mru-spaces = false` keeps Spaces from reordering by most-recent use.
- `system.defaults.spaces.spans-displays = false` keeps each display's Spaces separate.

The host also enables the standard macOS desktop switching shortcuts through
`com.apple.symbolichotkeys` so keyboard-synthesizing tools such as Logi Options
can trigger them reliably:

| Shortcut | Action |
| --- | --- |
| `Control+Left Arrow` | Move left a Space / previous desktop |
| `Control+Right Arrow` | Move right a Space / next desktop |

These are intentionally arrow-key shortcuts rather than letter shortcuts because
letter-based Mission Control hotkeys can be layout-sensitive under Colemak and
may not be reproduced correctly by external device software.

## Terminal Hotkey

`suremac` runs `skhd` as a Home Manager launchd agent for global macOS hotkeys.

| Shortcut | Action |
| --- | --- |
| `Command+Option+T` | Focus the configured dotfiles terminal, or launch it if it is not running |
| `Command+Option+B` | Focus a running browser, or open the default browser if none is running |
| `Command+Option+S` | Capture a selected screenshot region directly to the clipboard |
| `Command+Option+[` | Previous tab, emitted as `Command+Shift+[` |
| `Command+Option+]` | Next tab, emitted as `Command+Shift+]` |
| `Command+Option+N` | Mission Control (`N` is the Colemak-DH vertical-up key) |
| `Command+Option+E` | App Exposé (`E` is the Colemak-DH vertical-down key) |
| `Command+Option+Escape` | Lock screen |

The terminal target is derived from `dotfiles.gui.terminal`, so changing the
configured terminal package from WezTerm to Ghostty (or another terminal) also
changes what this hotkey focuses/launches. The helper uses the macOS app name
for known terminals (`WezTerm`, `Ghostty`) and the configured terminal command
for launching.

The browser hotkey prefers focusing an already-running browser from a known list
(Safari, Chrome, Firefox, Helium, Arc, Brave, Edge). If none are running, it
falls back to `open about:blank`, which launches the system default browser.

`skhd` requires macOS Accessibility permission. If the shortcut does nothing
after applying the config, enable `skhd` in **System Settings → Privacy &
Security → Accessibility** and restart the `skhd` launchd agent or log out and
back in.

## Raycast Configuration

Raycast does not expose a stable declarative config file for aliases and
hotkeys. Use Raycast's built-in sync for Raycast-managed configuration instead
of committing `.rayconfig` exports to this repository.
