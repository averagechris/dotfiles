{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.wallpaperd;
in {
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      wpaperd
    ];

    wayland.windowManager.hyprland.settings.exec-once =
      if cfg.enableHyprlandIntegration
      then [
        "${pkgs.wpaperd}/bin/wpaperd"
      ]
      else [];

    # The default section rotates every five minutes. The laptop panel
    # (eDP-1) pins one static image instead, to reduce battery impact.
    xdg.configFile."wpaperd/wallpaper.toml".text = ''
      [default]
      path = "${../wallpapers}"
      duration = "5m"
      sorting = "ascending"
      apply-shadow = true

      [eDP-1]
      path = "${../wallpapers}/05_nix-wallpaper-gear.png"
      apply-shadow = true
    '';
  };

  options.programs.wallpaperd = {
    enable = lib.mkEnableOption "Enable my dotfiles configured wallpaperd module.";
    enableHyprlandIntegration = lib.mkEnableOption "Enable the hyprland integration via hyprland exec-once.";
  };
}
