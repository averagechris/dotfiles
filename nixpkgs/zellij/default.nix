{
  config,
  lib,
  ...
}: let
  mkLayoutFile = file_name: {
    "zellij/layouts/${file_name}".source = ./layouts/${file_name};
  };
  merge = lib.foldl (a: b: a // b) {};
  layouts = with builtins; map mkLayoutFile (attrNames (readDir ./layouts));
in {
  xdg.configFile =
    (merge layouts)
    // {
      "zellij/themes/rose-pine.kdl".source = ./themes/rose-pine.kdl;
      "zellij/config.kdl".text =
        ''
          layout_dir "${config.xdg.configHome}/zellij/layouts"
          theme_dir "${config.xdg.configHome}/zellij/themes"
        ''
        + builtins.readFile ./config.kdl;
    };
}
