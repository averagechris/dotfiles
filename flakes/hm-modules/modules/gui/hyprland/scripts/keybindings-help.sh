#!/usr/bin/env bash
# Hyprland keybindings cheat sheet
# Displays all keybindings in an easy-to-read format

# Set terminal title for window matching
 echo -ne "\033]0;Hyprland Keybindings\007"

cat << 'EOF' | less -R
┌─────────────────────────────────────────────────────────────────────────────┐
│                         HYPRLAND KEYBINDINGS                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  MOD = SUPER KEY (Windows/Command)                                         │
│  Navigation: M=Left N=Down E=Up I=Right (Colemak-DH)                       │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ WINDOW MANAGEMENT                                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│  MOD+T              Open terminal                                           │
│  MOD+Q              Close active window                                     │
│  MOD+Shift+Q        Exit Hyprland                                           │
│  MOD+F              Toggle fullscreen                                       │
│  MOD+Shift+F        Toggle floating                                         │
│  MOD+Shift+P        Pin window (float on all workspaces)                    │
│  MOD+Space          Application launcher (anyrun)                             │
│  MOD+Tab            Cycle to next window                                    │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ WINDOW NAVIGATION (Colemak-DH)                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│  MOD+M              Focus left                                              │
│  MOD+N              Focus down                                              │
│  MOD+E              Focus up                                                │
│  MOD+I              Focus right                                             │
│  MOD+Shift+M        Swap window left                                        │
│  MOD+Shift+N        Swap window down                                        │
│  MOD+Shift+E        Swap window up                                          │
│  MOD+Shift+I        Swap window right                                       │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ WORKSPACES                                                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  MOD+1-9            Switch to workspace 1-9                                 │
│  MOD+0              Switch to workspace 10                                  │
│  MOD+Shift+1-9      Move window to workspace 1-9                            │
│  MOD+Shift+0        Move window to workspace 10                             │
│  MOD+Alt+M          Previous workspace                                      │
│  MOD+Alt+I          Next workspace                                          │
│  MOD+Scroll         Scroll through workspaces                               │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ SUBMAPS (Modes) - Press MOD + key to enter, ESC to exit                     │
├─────────────────────────────────────────────────────────────────────────────┤
│  MOD+A              Quick Actions menu:                                     │
│                       S=Signal  T=Telegram  K=KeePassXC                     │
│                       B=Zen     O=Obsidian  L=Lock                          │
│                       P=Pavucontrol  C=Color picker  D=Notifications        │
│                       W/Z=Eww bar    Y=Toggle layout    H/?=Help            │
│                       (focuses existing window or launches new)             │
│  MOD+R              Resize mode: M/N/E/I to resize, ESC to exit             │
│  MOD+S              Scratchpad mode: T=terminal S=scratchpad                │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ SPECIAL WORKSPACES                                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│  MOD+`              Toggle terminal scratchpad                              │
│  MOD+Shift+`        Move window to terminal scratchpad                      │
│  MOD+Escape         Return to previous workspace                            │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ SCREENSHOTS                                                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│  Print              Screenshot area (copy + save)                           │
│  Shift+Print        Screenshot output/monitor (copy + save)                 │
│  MOD+Print          Screenshot active window (copy + save)                  │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ MEDIA & BRIGHTNESS                                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│  XF86AudioMute      Toggle mute                                             │
│  XF86AudioRaiseVol  Volume up                                               │
│  XF86AudioLowerVol  Volume down                                             │
│  XF86AudioNext      Next track                                              │
│  XF86AudioPrev      Previous track                                          │
│  XF86AudioPlay      Play/Pause                                              │
│  XF86MonBrightness+ Brightness up                                           │
│  XF86MonBrightness- Brightness down                                         │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ OTHER                                                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│  MOD+C              Color picker (hyprpicker)                               │
│  MOD+MouseDrag      Move/resize windows                                     │
│                                                                             │
│  MOD+Shift+Ctrl+Alt+Space   Toggle QWERTY/Colemak-DH layout (mega keychord) │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

Press 'q' to close this help window
EOF
