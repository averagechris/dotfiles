{
  inputs,
  lib,
  pkgs,
  ...
}: let
  thornyStatus = pkgs.writeShellApplication {
    name = "thorny-status";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      gnused
      lm_sensors
      nix
      procps
      systemd
      tailscale
      util-linux
    ];
    text = ''
      set -uo pipefail

      section() { printf '\n== %s ==\n' "$*"; }

      section "Host"
      hostnamectl --static 2>/dev/null || hostname
      uptime

      section "Load and memory"
      printf 'Load average: '
      cut -d' ' -f1-3 /proc/loadavg
      free -h

      section "Disk"
      df -h / /nix 2>/dev/null || df -h /

      section "Nix store"
      du -sh /nix/store 2>/dev/null || true

      section "Active Nix builds"
      if pgrep -af 'nix build|nix-store|nix .*realise|nix .*realize|nix-daemon --stdio' >/dev/null; then
        pgrep -af 'nix build|nix-store|nix .*realise|nix .*realize|nix-daemon --stdio'
      else
        echo "No obvious active Nix build processes."
      fi

      section "Thermals"
      sensors 2>/dev/null || echo "No sensors output available."

      section "System76 power"
      systemctl --no-pager --lines=0 status system76-power.service 2>/dev/null \
        | sed -n '1,6p' \
        || echo "system76-power.service is unavailable or inactive."

      section "Tailscale"
      tailscale status --peers=false 2>/dev/null || echo "Tailscale status unavailable."
    '';
  };
in {
  imports = [
    inputs.nixos-modules.nixosModules.common
    inputs.nixos-modules.nixosModules.desktopCommon
    inputs.nixos-modules.nixosModules.networking
    inputs.nixos-modules.nixosModules.sound
    inputs.nixos-modules.nixosModules.sudoDeploy
    inputs.nixos-modules.nixosModules.tailscale
    inputs.nixos-modules.nixosModules.virtualization
    inputs.nixos-modules.nixosModules.isRemoteBuilder
    inputs.nixos-modules.nixosModules.users.chris
    inputs.nixos-modules.nixosModules.hyprlandDesktop
    ./hardware.nix
    inputs.agenix.nixosModules.default
    inputs.nixos-hardware.nixosModules.system76
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-gpu-amd
    inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate
    inputs.nixos-hardware.nixosModules.common-pc-ssd
  ];

  dotfiles.hyprland-desktop.enable = true;
  programs.hyprland.package = inputs.hyprland.packages.${pkgs.system}.hyprland;
  xdg.portal.extraPortals = lib.mkForce [
    inputs.hyprland.packages.${pkgs.system}.xdg-desktop-portal-hyprland
    pkgs.xdg-desktop-portal-gtk
  ];

  boot.initrd.luks.devices.root.device = "/dev/sda2";
  networking.hostName = "thorny";

  networking.wireless.interfaces = ["wlp6s0"];

  environment.systemPackages = with pkgs; [
    lm_sensors
    mesa
    nvme-cli
    smartmontools
    thornyStatus
  ];
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.enableRedistributableFirmware = true;
  hardware.system76.enableAll = true;

  # Allow thorny to build trainwreck's aarch64-linux system closure locally via
  # binfmt/QEMU when invoked directly on thorny, and allow other clients to use
  # thorny as an emulated aarch64-linux remote builder.
  boot.binfmt.emulatedSystems = ["aarch64-linux"];

  # Passwordless sudo for deploy-rs / remote rebuilds from trusted SSH keys.
  dotfiles.sudoNoPassword.enable = true;

  nix.settings = {
    # Thorny/thelio is intended to be a high-core-count remote builder. Allow
    # trusted SSH users to submit builds and let the local daemon use all CPUs.
    trusted-users = ["@wheel" "chris"];
    max-jobs = "auto";
    cores = 0;
    extra-platforms = ["aarch64-linux"];
    min-free = 20 * 1024 * 1024 * 1024;
    max-free = 100 * 1024 * 1024 * 1024;
  };

  services.fwupd.enable = true;

  # Thorny is a remote builder: displays may turn off and the session may lock,
  # but the machine itself should remain reachable for SSH and build jobs.
  services.logind.settings.Login.IdleAction = "ignore";
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  programs.steam.enable = true;
  programs.gamemode.enable = true;
  hardware.xone.enable = true;

  users.users.chris.extraGroups = ["libvirtd" "podman"];

  system.stateVersion = "26.05";
  home-manager.users.chris = {lib, ...}: {
    home.stateVersion = "26.05";
    imports = [
      inputs.hm-modules.homeManagerModules.default
      inputs.pip-chrome-extension.homeManagerModules.default
      inputs.hm-modules.homeManagerModules.ghostty-fix
    ];

    systemd.user.startServices = true;
    systemd.user.services = lib.listToAttrs (map (name:
      lib.nameValuePair name {
        Unit.RefuseManualStart = lib.mkForce true;
      }) [
      "hyprpaper"
      "hypridle"
      "swaync"
      "network-manager-applet"
      "udiskie"
      "mako"
      "gammastep"
      "com.mitchellh.ghostty"
      "mega-cmd-server-init"
    ]);

    dotfiles.hyprland-workstation.enable = true;
    dotfiles.hyprland-workstation.terminal = "ghostty";
    dotfiles.gui.swayidle.enable = false;
    dotfiles.gui.hyprland.waybar.enable = false;
    wayland.windowManager.hyprland.package = inputs.hyprland.packages.${pkgs.system}.hyprland;
    dotfiles.gui.hyprland.overview = {
      enable = false;
      package = null;
    };

    dotfiles.hypridle.timeouts = {
      dim = 600;
      lock = 1800;
      dpms = 2700;
      suspend = 0;
      hibernate = 0;
    };

    programs.meganz.enable = true;
    programs.helium.enable = true;
    programs.helium.extension-simple-pip-helper.enable = true;

    dotfiles.shell.yazi.enable = true;
    programs.opencode.enable = true;
    services.network-manager-applet.enable = true;
    home.packages = [pkgs.claude-code];
  };
}
