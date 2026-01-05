{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.nixos-modules.nixosModules.common
    inputs.nixos-modules.nixosModules.desktopCommon
    inputs.nixos-modules.nixosModules.docker
    inputs.nixos-modules.nixosModules.graphical
    inputs.nixos-modules.nixosModules.networking
    inputs.nixos-modules.nixosModules.sound
    inputs.nixos-modules.nixosModules.tailscale
    inputs.nixos-modules.nixosModules.virtualization
    inputs.nixos-modules.nixosModules.users.chris
    ./hardware.nix
    inputs.agenix.nixosModules.default
    inputs.nixos-hardware.nixosModules.system76
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate
    inputs.nixos-hardware.nixosModules.common-pc-ssd
  ];

  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;
  environment.sessionVariables = {
    COSMIC_DATA_CONTROL_ENABLED = 1;
    XDG_CURRENT_DESKTOP = "COSMIC";
    XDG_SESSION_DESKTOP = "COSMIC";
  };
  environment.systemPackages = with pkgs; [
    cosmic-ext-ctl
    cosmic-ext-tweaks
    examine
    system76-firmware
  ];

  boot.initrd.luks.devices = {
    root.device = "/dev/nvme1n1p2";
    root.preLVM = true;
  };

  # a regression around 25.11 broke this, i should be able to remove in the near future
  boot.kernel.sysctl."kernel.unprivileged_userns_clone" = 0;

  networking.hostName = "trap";

  hardware.graphics.enable = true;
  hardware.enableRedistributableFirmware = true;
  hardware.system76.enableAll = true;
  system.stateVersion = "24.11";
  home-manager.users.chris = {...}: {
    home.stateVersion = "24.11";
    imports = [
      inputs.hm-modules.homeManagerModules.default
    ];
    dotfiles.gui.enable = true;
    dotfiles.gui.sway.enable = false;
    dotfiles.gui.hyprland.enable = false;
    dotfiles.gui.swayidle.enable = false;
    dotfiles.shell.calibre-utils.enable = true;
    dotfiles.shell.python.enable = true;
    dotfiles.shell.pipx.enable = true;
    dotfiles.shell.yazi.enable = true;
    dotfiles.wezterm.enable = true;
    dotfiles.ghostty.enable = true;
    dotfiles.ghostty.service.enable = true;
    programs.helix.terminal.flavor = "wezterm";
    dotfiles.helix-terminal-tools = {
      enable = true;
      yazi = {
        enable = true;
        pickerWidth = 30;
        pickerSide = "left";
        helixKeybinding = "space.t.f"; # Toggle file picker
      };
    };
    programs.opencode.enable = true;
    programs.meganz.enable = true;
    programs.waybar.enable = false;

    # Ensure DBus uses the Nix-provided GTK portal backend instead of any Flatpak-exported one.
    # This avoids activation timeouts by pointing directly to the store binary.
    home.file.".local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.gtk.service".text = ''
      [D-BUS Service]
      Name=org.freedesktop.impl.portal.desktop.gtk
      Exec=${pkgs.xdg-desktop-portal-gtk}/libexec/xdg-desktop-portal-gtk
    '';

    # Import critical session env vars into user systemd and DBus, so DBus-activated
    # portal backends (gtk, etc.) inherit DISPLAY/WAYLAND env and don't hang.
    systemd.user.services."xdg-portal-env-import" = {
      Unit = {
        Description = "Import DISPLAY/WAYLAND env into user systemd and DBus";
        PartOf = ["graphical-session.target"];
        After = ["graphical-session.target"];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.dbus}/bin/dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE";
      };
      Install = {WantedBy = ["graphical-session.target"];};
    };

    # Pre-start the portal backends so the aggregator doesn't have to DBus-activate them
    # (works around DBus activation env issues).
    systemd.user.services."xdg-desktop-portal-gtk" = {
      Unit = {
        Description = "GTK xdg-desktop-portal backend";
        PartOf = ["graphical-session.target"];
        After = ["xdg-portal-env-import.service" "graphical-session.target"];
      };
      Service = {
        ExecStart = "${pkgs.xdg-desktop-portal-gtk}/libexec/xdg-desktop-portal-gtk";
        Restart = "on-failure";
      };
      Install = {WantedBy = ["graphical-session.target"];};
    };

    systemd.user.services."xdg-desktop-portal-cosmic" = {
      Unit = {
        Description = "COSMIC xdg-desktop-portal backend";
        PartOf = ["graphical-session.target"];
        After = ["xdg-portal-env-import.service" "graphical-session.target"];
      };
      Service = {
        ExecStart = "${pkgs.xdg-desktop-portal-cosmic}/libexec/xdg-desktop-portal-cosmic";
        Restart = "on-failure";
      };
      Install = {WantedBy = ["graphical-session.target"];};
    };
  };

  services.dbus.enable = true;
  services.flatpak.enable = true;
  services.fwupd.enable = true;

  xdg.portal = {
    enable = true;
    # Prefer COSMIC, keep GTK fallback for missing interfaces
    extraPortals = [pkgs.xdg-desktop-portal-cosmic pkgs.xdg-desktop-portal-gtk];
    config.common.default = ["cosmic" "gtk"];
  };

  fonts.enableDefaultPackages = true;
  fonts.packages = with pkgs; [dejavu_fonts font-awesome nerd-fonts.droid-sans-mono nerd-fonts.fira-code];

  users.users.chris.extraGroups = ["docker"];
}
