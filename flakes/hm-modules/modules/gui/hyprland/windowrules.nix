{
  config,
  lib,
  ...
}: let
  cfg = config.dotfiles.gui.hyprland;
  # makes strings like "title:<pattern>" or "window-id"
  mkPattern = {
    pattern,
    field,
    sep,
  }: "${field}${sep}${pattern}";

  # makes simple title matches like "title:^.*<pattern>.*$"
  titleContains = titlePattern:
    mkPattern {
      pattern = "^.*${titlePattern}.*$";
      field = "title";
      sep = ":";
    };
  classIs = name:
    if builtins.stringLength name > 0
    then "${mkPattern {
      pattern = "^.*${name}.*$";
      field = "class";
      sep = ":";
    }}"
    else "";

  # puts the above together producing a list of rules for each pattern
  # e.g. if you wanted to apply nodim and noblur to windows with YouTube in the title
  # or if they're a firefox Picture-in-Picture window
  # [
  #   ["nodim title:^.*YouTube.*$", "noblur title:^.*YouTube.*$"]
  #   ["nodim title:^.*Picture-in-Picture.*$",class:(firefox), "noblur title:^.*Picture-in-Picture.*$",class:(firefox)]
  # ]
  mkRules = patterns: rules: (map (rule: (map (pattern: "${rule} ${pattern}")) patterns) rules);
  floatWindows = {
    titles,
    class ? "",
  }:
    mkRules (map (title: lib.concatStringsSep " " (lib.filter (s: s != "") ["${classIs class}" "${titleContains title}"])) (lib.lists.toList titles)) ["float"];

  noDimWindowsTitled = {
    titles,
    class ? "",
  }:
    mkRules (map (title: lib.concatStringsSep " " (lib.filter (s: s != "") ["${classIs class}" "${titleContains title}"])) (lib.lists.toList titles)) ["nodim" "noblur"];
in {
  config = lib.mkIf cfg.enable {
    # https://wiki.hyprland.org/Configuring/Window-Rules/#rules
    # these end up
    wayland.windowManager.hyprland.settings.windowrule = lib.lists.flatten [
      (floatWindows {
        # these won't auto-float unless it's the initial class
        # https://github.com/hyprwm/Hyprland/issues/2687
        titles = "Picture-in-Picture";
        class = "firefox";
      })
      # Temporarily disabled noDimWindowsTitled due to syntax issues
      # (noDimWindowsTitled {titles = ["YouTube" "Picture-in-Picture"];})

      # Scratchpad window rules
      "float class:^(scratchpad-.*)$"
      "size 80% 80% class:^(scratchpad-.*)$"
      "center class:^(scratchpad-.*)$"
      "animation slide class:^(scratchpad-.*)$"

      # Terminal scratchpad specific
      "float class:^(scratchpad-terminal)$"
      "size 80% 70% class:^(scratchpad-terminal)$"

      # Music scratchpad specific (for spotify, cider, etc)
      "float title:^(Spotify.*)$"
      "size 70% 80% title:^(Spotify.*)$"

      # Picture-in-Picture
      "float title:^(Picture-in-Picture)$"
      "pin title:^(Picture-in-Picture)$"
      "size 480 270 title:^(Picture-in-Picture)$"
      "move 100%-490 100%-280 title:^(Picture-in-Picture)$"
      # Removed problematic rules: nodim, noblur, noinitialfocus

      # MPV video player
      "float class:^(mpv)$"
      "size 960 540 class:^(mpv)$"
      "center class:^(mpv)$"

      # Steam and gaming
      "fullscreen class:^(steam_app_.*)$"
      "immediate class:^(steam_app_.*)$"
      # Removed problematic rules: noblur, noshadow

      # Pavucontrol (audio control)
      "float class:^(pavucontrol)$"
      "size 800 600 class:^(pavucontrol)$"
      "center class:^(pavucontrol)$"

      # File dialogs
      "float title:^(Open File)$"
      "float title:^(Save File)$"
      "float title:^(Open Folder)$"
      "size 800 600 title:^(Open File)$"
      "size 800 600 title:^(Save File)$"
      "center title:^(Open File)$"
      "center title:^(Save File)$"

      # Calculator
      "float class:^(qalculate-gtk)$"
      "size 400 500 class:^(qalculate-gtk)$"

      # Image viewer (imv)
      "float class:^(imv)$"
      "size 80% 80% class:^(imv)$"
      "center class:^(imv)$"

      # Signal - chat workspace (9), float dialogs
      "workspace 9 silent class:^(signal)$"
      "float class:^(signal)$ title:^(Signal)$"
      "size 1000 700 class:^(signal)$ title:^(Signal)$"
      "center class:^(signal)$ title:^(Signal)$"

      # Telegram - chat workspace (9), float dialogs
      "workspace 9 silent class:^(telegramdesktop)$"
      "float class:^(telegramdesktop)$ title:^(Telegram)$"
      "size 1000 700 class:^(telegramdesktop)$ title:^(Telegram)$"
      "center class:^(telegramdesktop)$ title:^(Telegram)$"

      # KeePassXC - float and center for quick access
      "float class:^(org.keepassxc.KeePassXC)$"
      "size 900 600 class:^(org.keepassxc.KeePassXC)$"
      "center class:^(org.keepassxc.KeePassXC)$"
      "pin class:^(org.keepassxc.KeePassXC)$ title:^(Unlock Database)$"

      # Keybindings help window - float and center
      "float title:^(Hyprland Keybindings)$"
      "size 900 700 title:^(Hyprland Keybindings)$"
      "center title:^(Hyprland Keybindings)$"
    ];
  };
}
