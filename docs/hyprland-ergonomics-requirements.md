# Hyprland Ergonomics Requirements

This document captures the planned tater/shared Hyprland ergonomics work before implementation. The goal is to turn several awkward window-management flows into one coherent command surface, backed by a repo-managed Rust CLI/daemon rather than a pile of one-off scripts.

## Decisions

- Build a single Rust CLI/daemon named `hctl`.
- Generate `hctl`'s configuration from Nix into a JSON file rather than baking behavior into ad hoc scripts or command-line arguments.
- Use a mixed workspace model:
  - ordinary named workspaces for persistent homes such as `chat`
  - special/scratch-style workspaces where overlay semantics are useful
- KeePassXC should use native tray behavior, not a permanent Hyprland workspace home.
- Signal/Telegram quick access should move the real app window into the current workspace, then return it to its `chat` home.
- Smart gaps should be aggressive/spacious on large external monitors for 1-2 windows.
- Eww integration should prioritize a real system tray, while still exposing focused custom indicators where useful.
- Place the Rust helper using the same broad pattern as the existing repo-managed `jj-workflow` helper: colocated with the Home Manager module that owns the workflow.
- Represent launch commands as argv lists, not shell strings.
- For MVP, derive borrow state from current Hyprland clients and configured app homes; add persisted exact-restore state later only if needed.
- For MVP, have the daemon write JSON state for Eww instead of starting with polling.
- Match smart-gap monitor profiles by width first; add exact monitor-name matching later if width-based matching is not precise enough.
- Model hide behavior as an enum from day one, but initially implement only `close-to-tray`.

## High-level goals

- Provide predictable summon/dismiss behavior for utility apps.
- Provide persistent home workspaces for communication apps, plus quick borrow/return workflows for contextual use.
- Make modal keybindings and scratch/borrowed states more visible in Eww.
- Improve large-monitor ergonomics by dynamically increasing gaps for sparse workspaces.
- Keep the implementation testable and discoverable through one CLI.

## Proposed command surface

Use a verb-first command surface so keybindings read like actions:

```text
hctl daemon
hctl summon keepassxc
hctl hide keepassxc
hctl borrow signal
hctl return signal
hctl toggle-borrow telegram
hctl goto chat
hctl video-pin
hctl toggle-pin
hctl zen-terminal
hctl state eww
```

The CLI should talk to Hyprland through `hyprctl` and/or Hyprland sockets. The daemon should subscribe to Hyprland events when possible instead of polling constantly.

## Nix-generated configuration

The Home Manager module should generate a JSON config file for `hctl`, likely under the XDG config directory:

```text
~/.config/hctl/config.json
```

The binary should default to this path, with an override for tests and manual debugging:

```text
hctl --config /path/to/config.json state eww
```

The Nix option namespace should remain explicit even though the binary is short:

```nix
dotfiles.hyprland.hctl = {
  enable = true;

  apps = {
    keepassxc = {
      match.class = "org.keepassxc.KeePassXC";
      launch = ["keepassxc"];

      summon = {
        enable = true;
        floating = true;
        center = true;
        size = {
          width = 900;
          height = 650;
        };
      };

      hide = {
        enable = true;
        method = "close-to-tray";
      };
    };

    signal = {
      match.class = "Signal";
      launch = ["signal-desktop"];
      homeWorkspace = "chat";

      borrow = {
        enable = true;
        floating = true;
        center = true;
        size = {
          width = 900;
          height = 1000;
        };
      };
    };

    telegram = {
      match.class = "org.telegram.desktop";
      launch = ["telegram-desktop"];
      homeWorkspace = "chat";

      borrow = {
        enable = true;
        floating = true;
        center = true;
        size = {
          width = 900;
          height = 1000;
        };
      };
    };
  };

  workspaces = {
    chat = {
      name = "chat";
      kind = "named";
    };
  };

  smartGaps = {
    enable = true;
    profiles = {
      laptop = {
        maxMonitorWidth = 1999;
        gaps = {
          oneWindow = { inner = 12; outer = 32; };
          twoWindows = { inner = 10; outer = 24; };
          manyWindows = { inner = 8; outer = 12; };
        };
      };

      externalLarge = {
        minMonitorWidth = 2000;
        gaps = {
          oneWindow = { inner = 28; outer = 180; };
          twoWindows = { inner = 22; outer = 120; };
          threeWindows = { inner = 16; outer = 72; };
          manyWindows = { inner = 8; outer = 24; };
        };
      };
    };
  };
};
```

The generated JSON should be treated as the runtime API between Nix and Rust. `hctl` should not need to evaluate Nix or know about Nix modules.

### Runtime JSON schema v1

The generated JSON should use stable, Rust-friendly shapes. A representative v1 config should look like this:

```json
{
  "apps": {
    "keepassxc": {
      "match": {
        "class": "org.keepassxc.KeePassXC",
        "title": null,
        "initialClass": null,
        "initialTitle": null
      },
      "launch": ["keepassxc"],
      "homeWorkspace": null,
      "summon": {
        "enabled": true,
        "floating": true,
        "center": true,
        "size": {
          "width": 900,
          "height": 650
        }
      },
      "hide": {
        "enabled": true,
        "method": "close-to-tray"
      },
      "borrow": {
        "enabled": false
      }
    },
    "signal": {
      "match": {
        "class": "Signal",
        "title": null,
        "initialClass": null,
        "initialTitle": null
      },
      "launch": ["signal-desktop"],
      "homeWorkspace": "chat",
      "borrow": {
        "enabled": true,
        "floating": true,
        "center": true,
        "size": {
          "width": 900,
          "height": 1000
        }
      }
    }
  },
  "workspaces": {
    "chat": {
      "name": "chat",
      "kind": "named"
    }
  },
  "smartGaps": {
    "enabled": true,
    "profiles": [
      {
        "name": "laptop",
        "match": {
          "maxWidth": 1999
        },
        "gaps": {
          "oneWindow": { "inner": 12, "outer": 32 },
          "twoWindows": { "inner": 10, "outer": 24 },
          "threeWindows": { "inner": 8, "outer": 12 },
          "manyWindows": { "inner": 8, "outer": 12 }
        }
      },
      {
        "name": "externalLarge",
        "match": {
          "minWidth": 2000
        },
        "gaps": {
          "oneWindow": { "inner": 28, "outer": 180 },
          "twoWindows": { "inner": 22, "outer": 120 },
          "threeWindows": { "inner": 16, "outer": 72 },
          "manyWindows": { "inner": 8, "outer": 24 }
        }
      }
    ]
  },
  "eww": {
    "stateFile": "$XDG_STATE_HOME/hctl/eww-state.json"
  }
}
```

Implementation notes:

- `launch` is always an argv list. `hctl` should execute it directly, not through a shell.
- `match` starts with class/title fields from Hyprland client JSON. Matching should be exact by default; regex/glob matching can be added later if needed.
- `hide.method` is an enum. MVP implements only `close-to-tray`; future options may include `minimize`, `move-to-workspace`, or `move-to-special`.
- Borrowed state is derived in MVP: an app with `homeWorkspace = "chat"` is considered borrowed when its matched window is mapped on another workspace.
- The daemon should expand `$XDG_STATE_HOME` when writing Eww state. If unset, it should follow the XDG default of `~/.local/state`.
- Width-based smart-gap profile matching is the MVP behavior. Monitor-name matching can be added later without changing the basic profile structure.

## Runtime state and Eww interface

The daemon should write Eww-facing state to:

```text
$XDG_STATE_HOME/hctl/eww-state.json
```

This file should be cheap for Eww to read and should contain the current state Eww needs to render indicators. A representative shape:

```json
{
  "activeWorkspace": {
    "id": 3,
    "name": "chat",
    "kind": "named",
    "windowCount": 2,
    "empty": false
  },
  "apps": {
    "keepassxc": {
      "running": true,
      "mapped": false,
      "workspace": null
    },
    "signal": {
      "running": true,
      "mapped": true,
      "workspace": "3",
      "homeWorkspace": "chat",
      "borrowed": true
    }
  },
  "smartGaps": {
    "profile": "externalLarge",
    "inner": 22,
    "outer": 120,
    "tiledWindowCount": 2
  },
  "mode": {
    "name": null
  }
}
```

`hctl state eww` can still exist for debugging and manual inspection, but the MVP Eww integration should be daemon-file based rather than polling-first.

## Requirements checklist

### Architecture

- [ ] Add a repo-managed Rust package for `hctl` in the Home Manager module area or another shared package location.
- [ ] Place `hctl` using the same broad pattern as the existing repo-managed `jj-workflow` helper: near the Home Manager module that owns the workflow.
- [ ] Package the tool through Nix and expose it to the shared Hyprland configuration.
- [ ] Generate `~/.config/hctl/config.json` from `dotfiles.hyprland.hctl` options.
- [ ] Add a `--config` flag for tests and debugging alternate config files.
- [ ] Provide subcommands for one-shot actions and a `daemon` subcommand for event-driven behavior.
- [ ] Use structured state internally for Hyprland clients, monitors, workspaces, and active submaps.
- [ ] Prefer event subscription for daemon behavior; use polling only as a fallback.
- [ ] Add dry-run/logging support for commands that move/resize windows.
- [ ] Keep host-specific tuning configurable from Nix, especially for tater's laptop panel vs Dell monitor behavior.
- [ ] Execute configured launch commands as argv lists without shell interpolation.

### KeePassXC summon/dismiss

- [ ] Configure KeePassXC for native tray behavior: show tray icon, minimize/close to tray where supported.
- [ ] Add a summon command that launches or reveals KeePassXC.
- [ ] When summoned, move KeePassXC to the current workspace.
- [ ] Float, center, focus, and resize KeePassXC to a reasonable size.
- [ ] Add a hide command that returns KeePassXC to tray via app-native close/minimize behavior.
- [ ] Represent hide behavior as an enum in config and Rust, initially implementing only `close-to-tray`.
- [ ] Add keybindings for summon and hide.
- [ ] Add an Eww affordance for KeePassXC, even if the full system tray becomes the primary UI.

### Chat workspace and borrow/return

- [ ] Define a persistent `chat` workspace for Signal, Telegram, and future chat apps.
- [ ] Add window rules so Signal and Telegram default to the `chat` workspace.
- [ ] Add a command/keybinding to jump to the `chat` workspace.
- [ ] Add `borrow` behavior that moves the real Signal/Telegram window into the current workspace.
- [ ] Borrowed chat windows should float, focus, and receive monitor-aware size/position.
- [ ] Add toggle behavior: if the borrowed app is already on the current workspace, return it home.
- [ ] Return behavior should move the app back to `chat` and restore the preferred chat layout.
- [ ] Derive borrowed/home state from current clients and configured home workspaces for MVP; do not persist exact previous geometry yet.
- [ ] Preserve drag-and-drop ergonomics for screenshots/files by ensuring borrowed windows are real windows on the current workspace, not just hidden overlays.

### Smart video pinning

- [ ] Add a command for focused-window smart video pinning.
- [ ] The command should float the focused window, resize it to a sensible video aspect/size, move it to a good corner, and pin it.
- [ ] Size should be monitor-aware, e.g. larger on Dell/external monitors and smaller on the laptop panel.
- [ ] Add a separate generic pin toggle command/keybinding.
- [ ] Bind these into the mnemonic window/action mode.

### Smart gaps and zen terminal

- [ ] Add daemon logic that reacts to workspace/client/monitor changes.
- [ ] Count tiled windows on the active workspace and determine active monitor dimensions.
- [ ] Match smart-gap profiles by monitor width for MVP.
- [ ] Apply aggressive spacious gaps for sparse workspaces on large external monitors.
- [ ] Shrink gaps as window count increases.
- [ ] Keep laptop-panel gaps less aggressive.
- [ ] Make smart gaps easy to disable from Nix.
- [ ] Add a manual `zen-terminal` action for the focused terminal: float, center, and size to a comfortable large-monitor terminal shape.
- [ ] Decide after testing whether `zen-terminal` should be a toggle that restores tiling.

### Eww and tray integration

- [ ] Research and choose a real Wayland-compatible system tray strategy for Eww/bar usage.
- [ ] Add or integrate the chosen system tray implementation.
- [ ] Expose daemon state for Eww via `$XDG_STATE_HOME/hctl/eww-state.json`.
- [ ] Show scratch/chat workspace state, including empty special/named workspaces.
- [ ] Show borrowed chat app state, e.g. Signal or Telegram currently borrowed away from `chat`.
- [ ] Show active modal/submap keybinding hints when in action/window/chat modes.
- [ ] Consider a hover/click cheat-sheet widget for advanced keybindings.

### Keybinding requirements

- [ ] Keep the existing mnemonic/modal philosophy.
- [ ] Add chat mode bindings for `chat` workspace, Signal borrow, and Telegram borrow.
- [ ] Add password/KeePassXC summon/hide bindings.
- [ ] Add window mode bindings for generic pin, smart video pin, and zen terminal.
- [ ] Ensure every submap has an explicit Escape/reset binding.
- [ ] Document all new keybindings in `docs/hyprland.md` when implemented.

### Testing and validation

- [ ] Add unit tests for parsing Hyprland JSON state where practical.
- [ ] Add test fixtures for clients, monitors, and workspaces.
- [ ] Validate command behavior manually on tater's laptop panel.
- [ ] Validate command behavior manually on tater with the Dell monitor.
- [ ] Run formatting/linting after implementation.
- [ ] Run an appropriate tater or shared Home Manager build/check before shipping.

## MVP phases

### MVP 1: CLI, config, and one-shot actions

- [ ] Build and install `hctl` from Nix.
- [ ] Generate a JSON config file from Nix.
- [ ] Implement `hctl --help` and the verb-first command structure.
- [ ] Implement Hyprland state discovery for clients, monitors, and active workspace.
- [ ] Implement `hctl summon keepassxc` and `hctl hide keepassxc`.
- [ ] Implement `hctl borrow signal`, `hctl return signal`, `hctl borrow telegram`, and `hctl return telegram`.
- [ ] Implement `hctl video-pin`, `hctl toggle-pin`, and `hctl zen-terminal`.
- [ ] Implement daemon-written Eww state at `$XDG_STATE_HOME/hctl/eww-state.json`.
- [ ] Implement `hctl state eww` as a debugging command that prints the same state shape.

### MVP 2: daemon and smart state

- [ ] Implement `hctl daemon`.
- [ ] Subscribe to Hyprland events for workspace/client/monitor changes.
- [ ] Apply daemon-driven smart gaps.
- [ ] Write or serve state for Eww without requiring heavy polling.
- [ ] Add active mode/submap hints if Hyprland exposes the necessary events reliably.

### MVP 3: system tray and polish

- [ ] Research Eww-compatible Wayland StatusNotifier/system tray options.
- [ ] Integrate the selected tray approach.
- [ ] Polish KeePassXC tray/summon behavior based on real-world testing.
- [ ] Tune tater monitor profiles after using the Dell monitor and laptop panel.

## Open questions

- What exact command/package path should `hctl` live under?
- Which Rust crates should be used for CLI parsing, JSON, daemon event handling, and logging?
- Which system tray implementation works best with the current Eww/bar setup on Wayland?
- Should the chat home layout be floating-arranged or normal tiled layout after return?
- Should smart gaps be driven purely by focused monitor/workspace, or should it try to handle multiple visible monitors independently if Hyprland supports the needed controls?

## Initial implementation order

1. Package a minimal `hctl` Rust CLI with `--help` and placeholder subcommands.
2. Add Nix options and generate `~/.config/hctl/config.json`.
3. Implement Hyprland state discovery: clients, monitors, active workspace.
4. Implement KeePassXC summon/hide.
5. Implement chat workspace and borrow/return for Signal and Telegram.
6. Implement smart video pin and generic pin toggle.
7. Implement daemon-driven smart gaps.
8. Implement Eww state output and modal/keybinding hints.
9. Research and integrate the system tray path.
10. Tune tater-specific monitor profiles and update user-facing Hyprland documentation.
