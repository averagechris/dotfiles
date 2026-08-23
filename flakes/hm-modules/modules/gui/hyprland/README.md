# Hyprland window manager module

This module configures the Hyprland Wayland compositor: Colemak-DH keybindings with modal submaps, the hctl ergonomics daemon, Eww bar coordination, hyprlock locking, animations, gestures, and window rules. It renders plain Hyprlang (`configType = "hyprlang"`) instead of Home Manager's Lua output because Hyprland 0.54 can start from the Lua config while registering none of its bindings.

Full user guide and troubleshooting: [docs/hyprland.md](../../../../../docs/hyprland.md).

## Enable it

```nix
{
  dotfiles.gui.hyprland.enable = true;
}
```

The hm-modules flake exports this module as `homeManagerModules.gui.hyprland`. Enabling it also turns on, by default, the shared swayidle unit, hyprpaper, mako, and blueman-applet. Each of those defaults uses `mkDefault`, so a host config can override any of them.

## Options

All options live under `dotfiles.gui.hyprland`.

| Option | Type | Default | Purpose |
|--------|------|---------|---------|
| `enable` | bool | `false` | Apply the whole configuration |
| `waybar.enable` | bool | `true` | Run the full Waybar bar |
| `waybar.trayOnly.enable` | bool | `false` | Add a tray-only Waybar overlay next to the Eww bar |
| `overview.enable` | bool | `false` | Load the Hyprspace overview plugin |
| `overview.package` | package or null | `null` | Hyprspace build matching your Hyprland package |
| `hctl.enable` | bool | `true` | Install and run the hctl CLI and daemon |
| `hctl.package` | package | built from `./hctl` | hctl derivation to install |
| `hctl.apps` | attrs | KeePassXC, Signal, Telegram rules | App summon, hide, borrow, and launch behavior passed to hctl |
| `hctl.workspaces` | attrs | one named workspace, `chat` | Workspace definitions passed to hctl |
| `hctl.smartGaps.enable` | bool | `true` | Adjust gaps per monitor and per tiled window count |
| `hctl.smartGaps.profiles` | list of attrs | see below | Monitor-name and width-matched gap profiles |
| `hctl.smartGaps.resetGaps` | attrs | inner `4`, outer `6` | Base gaps restored when smart gaps are off for a workspace |
| `hctl.eww.stateFile` | string | `$XDG_STATE_HOME/hctl/eww-state.json` | Where the daemon writes Eww-facing JSON state |
| `animations.enable` | bool | `true` | Window, border, fade, and workspace animations |
| `gestures.enable` | bool | `true` | Three-finger horizontal swipe switches workspaces |
| `theme.colors` | attrs of strings | Rose Pine Moon palette | Named colors other modules can read |

Default smart-gap profiles match `eDP-1` (laptop panel) and `DP-2` (Dell dock) by name, then fall back to width: monitors narrower than 2000 px use laptop gaps, wider ones use external-large gaps.

## What you get

### Packages and scripts

Installs imv, libnotify, mpv, pavucontrol, playerctl, pulseaudio, wl-clipboard, wofi, hyprpicker, hyprsunset, hyprsysteminfo, grimblast, swaynotificationcenter, btop, hyprlock, and hctl when enabled. The shared screenshot import adds grim, slurp, swappy, and a swappy config saving to `~/screenshots`. Three helpers are defined inline:

- `hyprland-keybindings-help`: prints the full cheat sheet through `less`
- `hyprland-workspace-overview`: wofi menu to jump to a workspace or move the focused window there
- `focus-or-launch`: focuses an existing window class or launches the app

### Services

- `hyprpaper` for wallpapers
- `mako` notifications anchored top-center with a 2750 ms timeout
- `blueman-applet` for Bluetooth
- the hctl daemon as a systemd user service bound to `graphical-session.target` with `RefuseManualStart`, so rebuilds never start it outside a graphical session
- gammastep and wallpaperd stay off unless a host enables them; hyprsunset runs at 4500 K instead

Startup apps (`exec-once`): `anyrun daemon`, `hyprpaper`, `hyprsunset -t 4500`, and `signal-desktop --start-in-tray` when `programs.signal.enable` is true.

### Compositor setup

- Workspaces 1-5 pin to `DP-2`, 6-10 to `eDP-1`, plus a named `chat` workspace on `DP-2`; workspaces stay monitor-local when docked
- US Colemak-DH primary layout with plain US secondary, numlock on, natural scroll, touchpad scroll factor 0.5 with middle-button emulation and clickfinger behavior
- Dwindle layout with pseudotile, split preservation, and smart resizing
- 2 px borders with a Rose Pine Moon gradient, 8 px rounding, blur (size 4, two passes), inactive dimming at 0.15 strength, shadows, base gaps 4 inner and 6 outer
- Variable refresh rate, no logo or splash, displays wake on input, animated resizes and window drags
- XWayland and systemd session integration

Window rules float and size Firefox Picture-in-Picture (pinned bottom-right), mpv, pavucontrol, file dialogs, qalculate-gtk, imv, and KeePassXC; Steam games open fullscreen with immediate rendering; Signal and Telegram open silently on the `chat` workspace; classes matching `scratchpad-*` float centered at 80% size.

## Bar, lock, and idle

- **Eww bar.** A lid and display script keeps exactly one bar visible: `bar-internal` on `eDP-1`, or `bar-external-dp1`, `bar-external`, `bar-external-dp3`, `bar-external-hdmi-a-1`, or `bar-external-hdmi-a-2` on whichever external output is active. Quick actions keys `w` and `z` restart the bar. The widgets live in the separate Eww module; hctl feeds them state at `hctl.eww.stateFile`.
- **Lock screen.** hyprlock. Quick actions key `l` runs it, and closing the lid while no external monitor is connected runs it too.
- **Idle.** The shared swayidle unit locks with `swaylock -f -c 000000` after 180 seconds idle, suspends after 1200 seconds, and locks before sleep.
- **Lid switch.** Any lid event refreshes displays and bars: opening the lid enables `eDP-1`; closing it disables `eDP-1` only when another enabled monitor exists. Opening the lid also wakes displays with dpms on.

## Keybindings

`Super` is the main modifier. Navigation follows Colemak-DH home row positions: `m` left, `n` down, `e` up, `i` right. Bindings written with capital letters fire on the shifted key.

### Windows and launcher

| Keys | Action |
|------|--------|
| `Super+T` | Open the terminal configured in `dotfiles.gui.terminal` |
| `Super+Q` | Close the focused window |
| `Super+Shift+Q` | Exit Hyprland |
| `Super+F` | Toggle fullscreen |
| `Super+Shift+F` | Toggle floating |
| `Super+Shift+P` | Pin or unpin the focused window via `hctl toggle-pin` |
| `Super+Space` | Open anyrun |
| `Super+[` / `Super+]` | Lower or raise focused window opacity by 5% |
| `Super+Shift+]` | Reset focused window opacity |
| `Super+left button drag` | Move window |
| `Super+right button drag` | Resize window |

### Focus and workspaces

| Keys | Action |
|------|--------|
| `Super+m/n/e/i` | Move focus left, down, up, right |
| `Super+Shift+m/n/e/i` | Swap window left, down, up, right |
| `Super+1` through `Super+0` | Switch to workspace 1 through 10 |
| `Super+Shift+1` through `Super+Shift+0` | Move window to workspace 1 through 10 |
| `Super+Alt+m` / `Super+Alt+i` | Previous / next workspace |
| `Super+O` | Toggle the Hyprspace overview when enabled, otherwise open the wofi workspace overview |
| `Super+mouse left/right button` | Previous / next workspace |
| `` Super+` `` | Toggle the terminal scratchpad |
| `` Super+Shift+` `` | Move the focused window to the terminal scratchpad |
| `Super+Escape` | Return to the previous workspace |

### Submaps

Press the entry chord to enter a mode, then `Escape` to leave.

| Chord | Mode | Keys inside |
|-------|------|-------------|
| `Super+a` | quick actions | `s`/`t` borrow Signal/Telegram, `k` summon KeePassXC, `b` focus-or-launch Zen, `o` focus-or-launch Obsidian, `l` lock with hyprlock, `p` pavucontrol, `c` color picker, `d` toggle swaync, `w`/`z` restart the Eww bar, `y` cycle keyboard layout, `5` screenshot area, `h` or `?` keybindings help |
| `Super+r` | resize | `m/n/e/i` shrink width, grow height, shrink height, grow width; repeatable |
| `Super+s` | scratchpad | `t` terminal scratchpad, `Shift+t` move there, `s` general scratchpad, `Shift+s` move there, `k`/`p` summon KeePassXC, `Shift+k`/`Shift+p` hide it |
| `Super+c` | chat | `c` go to the `chat` workspace, `s` borrow Signal, `t` borrow Telegram |
| `Super+w` | window actions | `v` smart video pin, `z` zen window layout, `p` toggle pin, `g` toggle smart gaps, `o` opacity mode |
| `Super+w` then `o` | opacity | `n`/`e` lower/raise opacity, repeatable; `5` through `9` set 50% through 90%; `0` reset; `1` force 100% |

### Screenshots, media, and tools

| Keys | Action |
|------|--------|
| `Print` / `Shift+Print` / `Super+Print` | Screenshot area, whole output, or active window with grimblast, copied and saved |
| `XF86AudioRaiseVolume` / `XF86AudioLowerVolume` | Volume up or down 5% via pamixer |
| `XF86AudioMute` | Toggle mute via pamixer |
| `XF86AudioNext` / `XF86AudioPrev` | Next or previous track via playerctl |
| `XF86AudioStop` | Play or pause via playerctl |
| `XF86MonBrightnessUp` / `XF86MonBrightnessDown` | Brightness up or down 5% via brightnessctl |
| `Super+C` | Copy a color to the clipboard with hyprpicker |
| `Super+Shift+Ctrl+Alt+Space` | Cycle keyboard layouts |

Device blocks pin the built-in keyboard to Colemak-DH and the Dygma Defy to QWERTY, both with `resolve_binds_by_sym` so bindings keep working after a layout switch.

## Module files

| File | Purpose |
|------|---------|
| `default.nix` | Options, compositor settings, keybindings, submaps, packages, scripts, hctl service |
| `windowrules.nix` | Window-specific rules |
| `waybar.nix` | Optional Waybar full bar and tray-only surface |
| `wallpaperd.nix` | Optional wpaperd wallpaper rotation |
| `theme.nix` | Rose Pine Moon palette option |
| `animations.nix` | Animation curves |
| `gestures.nix` | Touchpad gestures |
| `hctl/` | Rust crate for the hctl CLI and daemon |
