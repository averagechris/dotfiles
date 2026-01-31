{
  inputs,
  pkgs,
  config,
  ...
}: {
  imports = [
    inputs.nixos-modules.nixosModules.common
    inputs.nixos-modules.nixosModules.desktopCommon
    inputs.nixos-modules.nixosModules.networking
    inputs.nixos-modules.nixosModules.sound
    inputs.nixos-modules.nixosModules.tailscale
    inputs.nixos-modules.nixosModules.virtualization
    inputs.nixos-modules.nixosModules.users.chris
    inputs.nixos-modules.nixosModules.hyprlandDesktop
    ./hardware.nix
    inputs.agenix.nixosModules.default
    # ThinkPad T14s Gen 5 AMD hardware support
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-t14-amd-gen5
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate
    inputs.nixos-hardware.nixosModules.common-gpu-amd
    inputs.nixos-hardware.nixosModules.common-pc-laptop
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
  ];

  # Enable Hyprland desktop environment
  dotfiles.hyprland-desktop.enable = true;

  # Agenix secrets
  age.secrets.openrouter-api-key = {
    file = ../../../secrets/openrouter-api-key.age;
    owner = "chris";
    group = "users";
    mode = "0400";
  };

  networking.hostName = "tater";

  # Fingerprint reader support
  services.fprintd.enable = true;
  security.pam.services.hyprlock.fprintAuth = true;

  # Firmware updates
  services.fwupd.enable = true;

  # Power management for ThinkPad
  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      START_CHARGE_THRESH_BAT0 = 75;
      STOP_CHARGE_THRESH_BAT0 = 80;
      WIFI_PWR_ON_AC = "off";
      WIFI_PWR_ON_BAT = "on";
    };
  };

  # Thermal management
  services.thermald.enable = true;

  # LUKS configuration is handled by disko (see disk-config.nix)

  hardware.graphics.enable = true;
  hardware.enableRedistributableFirmware = true;

  # Bluetooth support
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  system.stateVersion = "24.11";

  # Podman for rootless containers
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  # Gaming support
  programs.steam.enable = true;
  programs.gamemode.enable = true;
  hardware.graphics.enable32Bit = true;

  users.users.chris.extraGroups = ["libvirtd" "podman"];

  home-manager.users.chris = {...}: {
    home.stateVersion = "24.11";
    imports = [
      inputs.hm-modules.homeManagerModules.default
    ];

    # Use the unified Hyprland workstation configuration
    dotfiles.hyprland-workstation.enable = true;
    dotfiles.hyprland-workstation.terminal = "ghostty";

    # Additional tools
    dotfiles.shell.yazi.enable = true;
    programs.opencode.enable = true;
    dotfiles.opencode.openrouterApiKeyFile = config.age.secrets.openrouter-api-key.path;
    programs.meganz.enable = true;

    # Bluetooth and network management
    home.packages = [pkgs.overskride];
    services.network-manager-applet.enable = true;
  };
}
