{
  inputs,
  pkgs,
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
  age.secrets.gpg-private-key = {
    file = ../../../secrets/gpg-private-key.age;
    owner = "chris";
    group = "users";
    mode = "0400";
  };
  age.secrets.gpg-key-id = {
    file = ../../../secrets/gpg-key-id.age;
    owner = "chris";
    group = "users";
    mode = "0400";
  };

  networking.hostName = "tater";

  # Fingerprint reader support
  services.fprintd.enable = true;
  services.fprintd.tod.enable = true;
  services.fprintd.tod.driver = pkgs.libfprint-2-tod1-goodix;
  security.pam.services.hyprlock = {
    fprintAuth = false;
    unixAuth = true;
  };
  security.pam.services.greetd.fprintAuth = true;
  security.pam.services.regreet.fprintAuth = true;
  security.pam.services.sudo.fprintAuth = true;

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
      # MT7925e on Linux still appears to have intermittent disconnect/recovery
      # issues on some kernel + linux-firmware combinations, especially around
      # power saving / roaming / higher-band behavior. Keep Wi-Fi powersave off
      # on battery as a mitigation until this host remains stable across newer
      # nixpkgs/linux-firmware updates and firmware updates, at which point we
      # can retest and consider removing this override.
      WIFI_PWR_ON_BAT = "off";
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

  system.stateVersion = "26.05";

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

  home-manager.users.chris = {lib, ...}: let
    # GUI services that require a display and will hang during activation
    # These get RefuseManualStart=yes so sd-switch skips them, but they still
    # start normally via graphical-session.target when you log in
    guiServicesToSkip = [
      "blueman-applet"
      "hyprpaper"
      "hypridle"
      "swaync"
      "network-manager-applet"
      "udiskie"
      "mako"
      "gammastep"
      "com.mitchellh.ghostty"
      "mega-cmd-server-init"
    ];
    mkSkipDuringActivation = name:
      lib.nameValuePair name {
        Unit = {
          # Skip this service during home-manager activation (sd-switch respects this)
          # The service will still start normally via WantedBy when graphical session starts
          RefuseManualStart = lib.mkForce true;
        };
      };
  in {
    # secrets are passed via _module.args in nixos-modules/modules/users/chris.nix
    home.stateVersion = "26.05";
    imports = [
      inputs.hm-modules.homeManagerModules.default
      inputs.nix-openclaw.homeManagerModules.openclaw
      # Fix for openclaw node systemd service to prevent activation timeouts
      inputs.hm-modules.homeManagerModules.openclaw-fix
      # Fix for ghostty validation to prevent activation timeouts
      inputs.hm-modules.homeManagerModules.ghostty-fix
    ];

    # Keep service restarts enabled, but skip GUI services that hang without a display
    systemd.user.startServices = true;
    systemd.user.services = lib.listToAttrs (map mkSkipDuringActivation guiServicesToSkip);

    # Use the unified Hyprland workstation configuration
    dotfiles.hyprland-workstation.enable = true;
    dotfiles.hyprland-workstation.terminal = "ghostty";

    programs.hyprlock.settings.auth.fingerprint.enabled = true;

    # Prefer Hypridle + Hyprlock (disable swayidle/swaylock)
    dotfiles.gui.swayidle.enable = false;
    dotfiles.hypridle.timeouts = {
      dim = 120;
      lock = 300;
      dpms = 360;
      suspend = 420;
      hibernate = 1200;
    };

    # Disable waybar when using eww
    dotfiles.gui.hyprland.waybar.enable = false;

    # Additional tools
    dotfiles.shell.yazi.enable = true;
    programs.opencode.enable = true;
    dotfiles.opencode.openrouterApiKeyFile = "/run/agenix/openrouter-api-key";
    programs.meganz.enable = true;

    # GPG configuration with automatic key import
    dotfiles.gpg.enable = true;

    # Bluetooth and network management
    home.packages = [pkgs.overskride];
    services.network-manager-applet.enable = true;

    # Openclaw configuration (minimal base config for nodes)
    # DEBUG: All enabled (will likely timeout)
    programs.openclaw = let
      # Create minimal documents for node (required by module)
      documentsDir = pkgs.runCommand "openclaw-documents" {} ''
                mkdir -p $out
                echo "# AGENTS

        This is a node." > $out/AGENTS.md
                echo "# SOUL

        Node configuration." > $out/SOUL.md
                echo "# TOOLS

        Node tools." > $out/TOOLS.md
      '';
    in {
      # Required even for nodes to prevent activation script errors
      documents = documentsDir;

      # DEBUG: minimal instance enabled
      instances.minimal = {
        enable = true;
        stateDir = "~/.openclaw";
        workspaceDir = "~/.openclaw/workspace";
        systemd.enable = false;
        plugins = [];
      };

      # DEBUG: nodes enabled (this will likely cause timeout)
      nodes.default = {
        enable = true;
        gateway.host = "trainwreck";
        gateway.port = 18789;
        displayName = "Tater";
        stateDir = "~/.openclaw-node";
        systemd.enable = false;
      };
    };
  };
}
