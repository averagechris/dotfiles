{
  config,
  lib,
  ...
}: let
  mkLayoutFile = file_name: {
    xdg.configFile."zellij/layouts/${file_name}".source = "layouts/${file_name}";
  };
  merge = lib.foldl (a: b: a // b) {};
  layouts = with builtins; map mkLayoutFile (attrNames (readDir ./layouts));
in
  merge layouts
  // {
    programs.zellij.enable = true;
    programs.gitui.enable = true;

    xdg.configFile."zellij/config.kdl".text =
      ''
        layout_dir "${config.xdg.configHome}/zellij/layouts"
        theme_dir "${config.xdg.configHome}/zellij/themes"
      ''
      + builtins.readFile ./config.kdl;

    xdg.configFile."zellij/themes/rose-pine.kdl".source = ./themes/rose-pine.kdl;
  }
