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
    }},"
    else "";

  # puts the above together producing a list of rules for each pattern
  # e.g. if you wanted to apply nodim and noblur to windows with YouTube in the title
  # or if they're a firefox Picture-in-Picture window
  # [
  #   ["nodim,title:^.*YouTube.*$", "noblur,title:^.*YouTube.*$"]
  #   ["nodim,title:^.*Picture-in-Picture.*$",class:(firefox), "noblur,title:^.*Picture-in-Picture.*$",class:(firefox)]
  # ]
  mkRules = patterns: rules: (map (rule: (map (pattern: "${rule},${pattern}")) patterns) rules);
  floatWindows = {
    titles,
    class ? "",
  }:
    mkRules (map (title: "${classIs class}${titleContains title}") (lib.lists.toList titles)) ["float"];

  noDimWindowsTitled = {
    titles,
    class ? "",
  }:
    mkRules (map (title: "${classIs class}${titleContains title}") (lib.lists.toList titles)) ["nodim" "noblur"];
in {
  config = lib.mkIf cfg.enable {
    # https://wiki.hyprland.org/Configuring/Window-Rules/#rules
    # these end up
    wayland.windowManager.hyprland.settings.windowrulev2 = lib.lists.flatten [
      (floatWindows {
        # these won't auto-float unless it's the initial class
        # https://github.com/hyprwm/Hyprland/issues/2687
        titles = "Picture-in-Picture";
        class = "firefox";
      })
      (noDimWindowsTitled {titles = ["YouTube" "Picture-in-Picture"];})
    ];
  };
}
