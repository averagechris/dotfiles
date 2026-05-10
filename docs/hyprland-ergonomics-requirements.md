# Hyprland Ergonomics Requirements

This document captures the tater/shared Hyprland ergonomics plan and current implementation status. The goal is to turn several awkward window-management flows into one coherent command surface, backed by a repo-managed Rust CLI/daemon rather than a pile of one-off scripts.

## Current status

`hctl` now exists as a repo-managed Rust helper under the shared Hyprland Home Manager module:

```text
flakes/hm-modules/modules/gui/hyprland/hctl/
```

Implemented so far:

- Nix package/build for `hctl`.
- Nix-generated runtime config at `~/.config/hctl/config.json`.
- `dotfiles.gui.hyprland.hctl` Home Manager options for apps, workspaces, smart gaps, package override, and Eww state file path.
- User systemd service `hctl.service` running `hctl daemon`.
- Verb-first `hctl` command surface for summon/hide, borrow/return, workspace goto, pinning, video pinning, zen terminal, daemon, and Eww state inspection.
- Global `hctl --dry-run`/`-n` support for printing planned Hyprland dispatches/keywords without mutating window state.
- `hctl video-pin` is idempotent for already-pinned windows: it still reapplies video geometry, but does not toggle pin off.
- KeePassXC summon/hide behavior using app-native close-to-tray assumptions.
- Signal/Telegram persistent `chat` workspace and real-window borrow/return behavior.
- Smart gaps daemon behavior using exact monitor-name and width-based profiles.
- Event-driven daemon wakeups through Hyprland socket2, with polling fallback.
- Daemon smart-gap keyword writes are idempotent within a daemon run to avoid repeated gap churn on refresh events.
- Eww state JSON written to `$XDG_STATE_HOME/hctl/eww-state.json`.
- Eww widgets for named/special workspace context, chat borrowed state, and KeePassXC state.
- Mnemonic `Super+W` window-action bindings for video pinning, zen-window layout, and generic pin toggling.
- Tests for config parsing, app matching, workspace targeting, smart gaps, Eww state derivation, state path expansion, Hyprland socket path derivation, and event filtering.

Still pending or needing real-world tuning:

- Manual runtime validation on tater's laptop panel and Dell monitor.
- Verify exact KeePassXC tray show/hide behavior under real settings.
- Verify exact Signal/Telegram/Zen/window class behavior under Hyprland and keep app-class matches tuned.
- Tune smart gap sizes and chat/borrow window geometry after use.
- Tray direction implemented for tater: keep Eww as the primary bar and enable an adjacent tray-only Waybar StatusNotifier host, rather than trying to host tray icons inside Eww directly.
- Eww's active submap indicator includes mode-specific hover tooltips, including window-action hints, and opens the full keybinding help when clicked.

Runtime validation notes from the current tater session:

- Focused monitor was `DP-2` at `3840x2160`, so the `externalLarge` smart-gap profile selected as expected for one tiled window.
- KeePassXC exposed class and initial class `org.keepassxc.KeePassXC`, matching the configured app selector. It was visible on `special:scratchpad`; close-to-tray hide still needs an intentional interactive test with KeePassXC settings confirmed.
- Signal exposed class and initial class `signal` when launched manually during testing. The config/window rules now match that lowercase class, and `hctl` waits longer for slow chat app startup before giving up.
- The first Signal borrow attempt launched a real window but timed out before matching the late client, leaving it tiled. After the lowercase class fix and command-dispatch fix, `hctl borrow signal` floated, centered, and resized the live Signal window to `900x1000`; `hctl return signal` moved it back to `chat` and tiled it again.
- Telegram is exposed as `Telegram` in the current profile/Nix package metadata, so its launch argv now uses `Telegram` rather than `telegram-desktop`. After that fix, `hctl borrow telegram` launched/matched class `org.telegram.desktop`, floated, centered, and resized the window to `900x1000`; `hctl return telegram` moved it back to `chat` and tiled it again.
- Zen Browser exposed class and initial class `zen-beta`; `hctl video-pin` remains class-agnostic, but Zen pop-out/video-window geometry still needs an intentional focused-window test.

## Decisions

- Build a single Rust CLI/daemon named `hctl`.
- Generate `hctl`'s configuration from Nix into a JSON file rather than baking behavior into ad hoc scripts or command-line arguments.
- Use a mixed workspace model:
  - ordinary named workspaces for persistent homes such as `chat`
  - special/scratch-style workspaces where overlay semantics are useful
- KeePassXC should use native tray behavior, not a permanent Hyprland workspace home.
- Signal/Telegram quick access should move the real app window into the current workspace, then return it to its `chat` home.
- Smart gaps should be aggressive/spacious on large external monitors for 1-2 windows.
- Eww integration should keep focused custom indicators where useful and pair with an adjacent real StatusNotifier tray surface for app tray icons; tater uses the shared tray-only Waybar mode for that surface.
- Place the Rust helper using the same broad pattern as the existing repo-managed `jj-workflow` helper: colocated with the Home Manager module that owns the workflow.
- Represent launch commands as argv lists, not shell strings.
- For MVP, derive borrow state from current Hyprland clients and configured app homes; add persisted exact-restore state later only if needed.
- For MVP, have the daemon write JSON state for Eww instead of starting with polling.
- Match smart-gap monitor profiles by exact monitor name when configured, with width ranges as the fallback/default profile shape.
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
hctl zen-window
hctl state eww
hctl --dry-run video-pin
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

The Nix option namespace remains explicit even though the binary is short:

```nix
dotfiles.gui.hyprland.hctl = {
  enable = true;

  apps = {
    keepassxc = {
      match.class = "org.keepassxc.KeePassXC";
      launch = ["keepassxc"];

      summon = {
        enabled = true;
        floating = true;
        center = true;
        size = {
          width = 900;
          height = 650;
        };
      };

      hide = {
        enabled = true;
        method = "close-to-tray";
      };
    };

    signal = {
      match.class = "signal";
      launch = ["signal-desktop"];
      homeWorkspace = "chat";

      borrow = {
        enabled = true;
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
      launch = ["Telegram"];
      homeWorkspace = "chat";

      borrow = {
        enabled = true;
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
    profiles = [
      {
        name = "taterLaptopPanel";
        match.name = "eDP-1";
        gaps = {
          oneWindow = { inner = 12; outer = 32; };
          twoWindows = { inner = 10; outer = 24; };
          threeWindows = { inner = 8; outer = 12; };
          manyWindows = { inner = 8; outer = 12; };
        };
      }

      {
        name = "taterDellDock";
        match.name = "DP-2";
        gaps = {
          oneWindow = { inner = 28; outer = 180; };
          twoWindows = { inner = 22; outer = 120; };
          threeWindows = { inner = 16; outer = 72; };
          manyWindows = { inner = 8; outer = 24; };
        };
      }

      {
        name = "laptop";
        match.maxWidth = 1999;
        gaps = {
          oneWindow = { inner = 12; outer = 32; };
          twoWindows = { inner = 10; outer = 24; };
          threeWindows = { inner = 8; outer = 12; };
          manyWindows = { inner = 8; outer = 12; };
        };
      }

      {
        name = "externalLarge";
        match.minWidth = 2000;
        gaps = {
          oneWindow = { inner = 28; outer = 180; };
          twoWindows = { inner = 22; outer = 120; };
          threeWindows = { inner = 16; outer = 72; };
          manyWindows = { inner = 8; outer = 24; };
        };
      }
    ];
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
        "class": "signal",
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
        "name": "taterLaptopPanel",
        "match": {
          "name": "eDP-1"
        },
        "gaps": {
          "oneWindow": { "inner": 12, "outer": 32 },
          "twoWindows": { "inner": 10, "outer": 24 },
          "threeWindows": { "inner": 8, "outer": 12 },
          "manyWindows": { "inner": 8, "outer": 12 }
        }
      },
      {
        "name": "taterDellDock",
        "match": {
          "name": "DP-2"
        },
        "gaps": {
          "oneWindow": { "inner": 28, "outer": 180 },
          "twoWindows": { "inner": 22, "outer": 120 },
          "threeWindows": { "inner": 16, "outer": 72 },
          "manyWindows": { "inner": 8, "outer": 24 }
        }
      },
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
- `--dry-run` prints launch/dispatch/keyword operations and suppresses launch, dispatch, and keyword side effects while still reading Hyprland state when needed.
- `match` starts with class/title fields from Hyprland client JSON. Matching should be exact by default; regex/glob matching can be added later if needed.
- `hide.method` is an enum. MVP implements only `close-to-tray`; future options may include `minimize`, `move-to-workspace`, or `move-to-special`.
- Borrowed state is derived in MVP: an app with `homeWorkspace = "chat"` is considered borrowed when its matched window is mapped on another workspace.
- The daemon should expand `$XDG_STATE_HOME` when writing Eww state. If unset, it should follow the XDG default of `~/.local/state`.
- Smart-gap profiles can match an exact monitor `name` plus optional `minWidth`/`maxWidth` constraints. Existing width-only profiles continue to act as broad fallbacks.
- Borrow/summon action sizes are clamped to the focused monitor with a small margin so fixed defaults do not overflow smaller panels.
- Smart video pin placement uses the focused monitor's origin and dimensions rather than assuming the focused output starts at `(0, 0)`.

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

- [x] Add a repo-managed Rust package for `hctl` in the Home Manager module area or another shared package location.
- [x] Place `hctl` using the same broad pattern as the existing repo-managed `jj-workflow` helper: near the Home Manager module that owns the workflow.
- [x] Package the tool through Nix and expose it to the shared Hyprland configuration.
- [x] Generate `~/.config/hctl/config.json` from `dotfiles.gui.hyprland.hctl` options.
- [x] Add a `--config` flag for tests and debugging alternate config files.
- [x] Provide subcommands for one-shot actions and a `daemon` subcommand for event-driven behavior.
- [x] Use structured state internally for Hyprland clients, monitors, workspaces, and active submaps.
- [x] Prefer event subscription for daemon behavior; use polling only as a fallback.
- [x] Add dry-run/logging support for commands that move/resize windows.
- [ ] Keep host-specific tuning configurable from Nix, especially for tater's laptop panel vs Dell monitor behavior.
- [x] Execute configured launch commands as argv lists without shell interpolation.

### KeePassXC summon/dismiss

- [ ] Configure KeePassXC for native tray behavior: show tray icon, minimize/close to tray where supported.
- [x] Add a summon command that launches or reveals KeePassXC.
- [x] When summoned, move KeePassXC to the current workspace.
- [x] Float, center, focus, and resize KeePassXC to a reasonable size.
- [x] Add a hide command that returns KeePassXC to tray via app-native close/minimize behavior.
- [x] Represent hide behavior as an enum in config and Rust, initially implementing only `close-to-tray`.
- [x] Add keybindings for summon and hide.
- [x] Add an Eww affordance for KeePassXC, even if the full system tray becomes the primary UI.

### Chat workspace and borrow/return

- [x] Define a persistent `chat` workspace for Signal, Telegram, and future chat apps.
- [x] Add window rules so Signal and Telegram default to the `chat` workspace.
- [x] Add a command/keybinding to jump to the `chat` workspace.
- [x] Add `borrow` behavior that moves the real Signal/Telegram window into the current workspace.
- [x] Borrowed chat windows should float, focus, and receive monitor-aware size/position.
- [x] Add toggle behavior: if the borrowed app is already on the current workspace, return it home.
- [x] Return behavior should move the app back to `chat` and restore the preferred chat layout by tiling the returned app window.
- [x] Derive borrowed/home state from current clients and configured home workspaces for MVP; do not persist exact previous geometry yet.
- [x] Preserve drag-and-drop ergonomics for screenshots/files by ensuring borrowed windows are real windows on the current workspace, not just hidden overlays.

### Smart video pinning

- [x] Add a command for focused-window smart video pinning.
- [x] The command should float the focused window, resize it to a sensible video aspect/size, move it to a good corner, and pin it.
- [x] Avoid unpinning an already-pinned focused window when re-running smart video pinning.
- [x] Size should be monitor-aware, e.g. larger on Dell/external monitors and smaller on the laptop panel.
- [x] Add a separate generic pin toggle command/keybinding.
- [x] Bind smart video pinning into the mnemonic window/action mode.

### Smart gaps and zen terminal

- [x] Add daemon logic that reacts to workspace/client/monitor changes.
- [x] Count tiled windows on the active workspace and determine active monitor dimensions.
- [x] Match smart-gap profiles by monitor width for MVP.
- [x] Allow smart-gap profiles to target exact monitor names for tater/dock-specific tuning.
- [x] Apply aggressive spacious gaps for sparse workspaces on large external monitors.
- [x] Shrink gaps as window count increases.
- [x] Avoid repeating unchanged smart-gap keyword writes on every daemon refresh.
- [x] Keep laptop-panel gaps less aggressive.
- [x] Make smart gaps easy to disable from Nix.
- [x] Add a manual `zen-window` action for the focused window: toggle between tiled and centered/floating at a comfortable large-monitor shape.
- [x] Decide after testing whether `zen-terminal` should be a toggle that restores tiling; it is now `zen-window`, with `zen-terminal` kept as a deprecated compatibility alias.

### Eww and tray integration

- [x] Research and choose a real Wayland-compatible system tray strategy for Eww/bar usage.
- [x] Add or integrate the chosen system tray implementation.
- [x] Expose daemon state for Eww via `$XDG_STATE_HOME/hctl/eww-state.json`.
- [x] Show scratch/chat workspace state, including empty special/named workspaces.
- [x] Show borrowed chat app state, e.g. Signal or Telegram currently borrowed away from `chat`.
- [x] Show active modal/submap keybinding hints when in action/window/chat modes.
- [x] Add hover key hints to the active submap indicator for advanced modal bindings.
- [x] Add click-to-open detailed help from the active submap indicator.

### Keybinding requirements

- [x] Keep the existing mnemonic/modal philosophy.
- [x] Add chat mode bindings for `chat` workspace, Signal borrow, and Telegram borrow.
- [x] Add password/KeePassXC summon/hide bindings.
- [x] Add window mode bindings for smart video pin and zen terminal.
- [x] Ensure every submap has an explicit Escape/reset binding.
- [x] Document all new keybindings in `docs/hyprland.md` when implemented.

### Testing and validation

- [x] Add unit tests for parsing Hyprland JSON state where practical.
- [x] Add test fixtures for clients, monitors, and workspaces.
- [ ] Validate command behavior manually on tater's laptop panel.
- [ ] Validate command behavior manually on tater with the Dell monitor.
- [x] Run formatting/linting after implementation.
- [x] Run an appropriate tater or shared Home Manager build/check before shipping.

## MVP phases

### MVP 1: CLI, config, and one-shot actions

- [x] Build and install `hctl` from Nix.
- [x] Generate a JSON config file from Nix.
- [x] Implement `hctl --help` and the verb-first command structure.
- [x] Implement Hyprland state discovery for clients, monitors, and active workspace.
- [x] Implement `hctl summon keepassxc` and `hctl hide keepassxc`.
- [x] Implement `hctl borrow signal`, `hctl return signal`, `hctl borrow telegram`, and `hctl return telegram`.
- [x] Implement `hctl video-pin`, `hctl toggle-pin`, and `hctl zen-window`.
- [x] Implement daemon-written Eww state at `$XDG_STATE_HOME/hctl/eww-state.json`.
- [x] Implement `hctl state eww` as a debugging command that prints the same state shape.

### MVP 2: daemon and smart state

- [x] Implement `hctl daemon`.
- [x] Subscribe to Hyprland events for workspace/client/monitor changes.
- [x] Apply daemon-driven smart gaps.
- [x] Write or serve state for Eww without requiring heavy polling.
- [x] Add active mode/submap hints if Hyprland exposes the necessary events reliably.

### MVP 3: system tray and polish

- [x] Research Eww-compatible Wayland StatusNotifier/system tray options.
- [x] Integrate the selected tray approach.
- [ ] Polish KeePassXC tray/summon behavior based on real-world testing.
- [ ] Tune tater monitor profiles after using the Dell monitor and laptop panel.

## Open questions

- Does the top-right tray-only Waybar surface need monitor-specific placement tweaks after real tater runtime testing?
- Should the chat home layout be floating-arranged or normal tiled layout after return?
- Should smart gaps be driven purely by focused monitor/workspace, or should it try to handle multiple visible monitors independently if Hyprland supports the needed controls?

## Next slices

1. Runtime-test KeePassXC tray behavior, Signal/Telegram borrow/return, and Zen pop-out pinning on tater.
2. Tune smart gap profiles and borrowed chat geometry on the Dell monitor and laptop panel.
3. Improve daemon behavior if runtime testing shows event gaps beyond the current event subscription and idempotent smart-gap writes.
4. Runtime-test the tray-only Waybar StatusNotifier surface alongside the Eww bar and tune placement if needed.

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
