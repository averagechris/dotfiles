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
      ./helium.nix
      ./firefox.nix
      ./linux_desktop.nix
      ./hyprland
      ./kitty.nix
      ./macos-hotkeys.nix
      ./zed.nix
      ./wezterm
      ./ghostty
      # Hyprland ecosystem tools
      ./anyrun
      ./swaync
      ./hyprlock
      ./hypridle
      ./wlogout
      ./eww
      # Theming
      ./theming
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
      # Keep the base GUI module focused on shared desktop plumbing and common
      # apps. Workstation modules select exactly one terminal and hosts opt into
      # browsers explicitly, so enabling dotfiles.gui does not accidentally pull
      # in several terminal emulators or an unused browser.
      programs.keepassxc.enable = mkDefault cfg.enable;
      programs.signal.enable = mkDefault cfg.enable;
      programs.zoom.enable = mkDefault false;

      services.udiskie.enable = mkDefault isLinux;

      # Enabling this flag alone installs nothing; it adds the MegaSync
      # GUI app when programs.meganz is enabled.
      programs.meganz.gui.enable = mkDefault cfg.enable;

      # Programs without dedicated modules get installed through
      # home.packages when enabled.
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
