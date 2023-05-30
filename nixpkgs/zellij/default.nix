{config, ...}: {
  programs.zellij.enable = true;
  xdg.configFile."zellij/config.kdl".text =
    ''
      layout_dir "${config.xdg.configHome}/zellij/layouts"
      theme_dir "${config.xdg.configHome}/zellij/themes"
    ''
    + builtins.readFile ./config.kdl;
}
