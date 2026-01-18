{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  cfg = config.dotfiles.gui;
in
  with lib; {
    imports = [
      ./alacritty.nix
      ./cosmic-portal-workarounds.nix
      ./zoom.nix
      ./firefox.nix
      ./linux_desktop.nix
      ./hyprland
      ./kitty.nix
      ./zed.nix
      ./windsurf.nix
      ./wezterm
      ./ghostty
    ];
    options.dotfiles.gui = {
      enable = mkEnableOption "Enables the GUI window manager and apps that I've configured.";
      terminal = mkOption {
        type = types.submodule {
          options = {
            package = mkOption {
              type = types.package;
              description = "The terminal program to pass to the window manager, by default kitty.";
            };
            args = mkOption {
              type = types.listOf types.str;
              description = "The args passed to the invocation of the terminal program used by the window manager.";
            };
            binPath = mkOption {
              type = types.str;
              description = "The invocation of the terminal program used by the window manager.";
            };
          };
        };
        default = {
          inherit (config.programs.kitty) package;
          args = ["--single-instance" "--instance-group=0" "--listen-on=unix:/tmp/main-kitty-socket"];
          binPath = let inherit (config.dotfiles.gui.terminal) package args; in ''${package}/bin/${package.pname} ${builtins.concatStringsSep " " args}'';
        };
        description = "A submodule describing the terminal program passed to the window manager, by default kitty.";
      };
    };
    options.programs = {
      darktable.enable = mkEnableOption "Installs darktable.";
      signal.enable = mkEnableOption "Installs signal (the messaging app).";
      write-stylus.enable = mkEnableOption "Installs write_stylus.";
    };

    config = mkIf cfg.enable {
      # these programs we enable by default if gui.enable
      # but not all of the programs are (like write-stylus)
      programs.alacritty.enable = mkDefault cfg.enable;
      programs.kitty.enable = mkDefault cfg.enable;
      dotfiles.wezterm.enable = mkDefault cfg.enable;
      programs.darktable.enable = mkDefault cfg.enable;
      programs.firefox.enable = mkDefault cfg.enable;
      programs.keepassxc.enable = mkDefault cfg.enable;
      programs.signal.enable = mkDefault cfg.enable;
      programs.zoom.enable = mkDefault cfg.enable;

      services.udiskie.enable = mkDefault isLinux;

      # this doesn't install the program but makes it so the gui app
      # is installed if the program is enabled
      programs.meganz.gui.enable = mkDefault cfg.enable;

      # any of the programs that we're not creating config for we
      # just add to home.packages
      home.packages = with pkgs;
        (
          if config.programs.darktable.enable
          then [darktable]
          else []
        )
        ++ (
          if config.programs.keepassxc.enable
          then [git-credential-keepassxc]
          else []
        )
        ++ (
          if config.programs.signal.enable
          then [
            signal-desktop
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
