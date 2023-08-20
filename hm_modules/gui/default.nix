{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.gui;
in
  with lib; {
    imports = [
      ./alacritty.nix
      ./zoom.nix
      ./firefox.nix
      ./linux_desktop.nix
      ./sway
      ./hyprland
    ];
    options.dotfiles.gui = {
      enable = mkEnableOption "Enables the GUI window manager and apps that I've cofnigured.";
      terminal = mkOption {
        type = types.package;
        default = config.programs.alacritty.package;
        description = mdDoc "The terminal program to pass to the window manager, by default alacritty.";
      };
    };
    options.programs = {
      darktable.enable = mkEnableOption "Installs darktable.";
      keepassxc.enable = mkEnableOption "Installs keepassxc.";
      signal.enable = mkEnableOption "Installs signal (the messaging app).";
      write-stylus.enable = mkEnableOption "Installs write_stylus.";
    };

    config = mkIf cfg.enable {
      # these programs we enable by default if gui.enable
      # but not all of the programs are (like write-stylus)
      programs.alacritty.enable = mkDefault cfg.enable;
      programs.darktable.enable = mkDefault cfg.enable;
      programs.firefox.enable = mkDefault cfg.enable;
      programs.keepassxc.enable = mkDefault cfg.enable;
      programs.signal.enable = mkDefault cfg.enable;
      programs.zoom.enable = mkDefault cfg.enable;

      # use sway by default if gui is enabled
      dotfiles.gui.sway.enable = mkDefault cfg.enable;

      # this doesn't install the program but makes it so the gui app
      # is installed if the program is enabled
      programs.meganz.gui.enable = mkDefault cfg.enable;

      # any of the programs that we're not creating config for we
      # just add to home.packages
      home.packages = with pkgs;
        []
        ++ (
          if config.programs.darktable.enable
          then [darktable]
          else []
        )
        ++ (
          if config.programs.keepassxc.enable
          then [keepassxc git-credential-keepassxc]
          else []
        )
        ++ (
          if config.programs.signal.enable
          then [
            (signal-desktop.overrideAttrs (o: {
              preFixup =
                o.preFixup
                + ''
                  gappsWrapperArgs+=(
                    --add-flags "--enable-features=UseOzonePlatform"
                    --add-flags "--ozone-platform=wayland"
                    --add-flags "--enable-features=WaylandWindowDecorations"
                  )
                '';
            }))
          ]
          else []
        )
        ++ (
          if config.programs.write-stylus.enable
          then [write_stylus]
          else []
        );
    };
  }
