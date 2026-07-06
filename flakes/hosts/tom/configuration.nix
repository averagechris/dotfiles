{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.nixos-modules.nixosModules.common
    inputs.nixos-modules.nixosModules.desktopCommon
    inputs.nixos-modules.nixosModules.sudoDeploy
    inputs.nixos-modules.nixosModules.selfDeploy
    inputs.nixos-modules.nixosModules.tailscale
    inputs.nixos-modules.nixosModules.useRemoteBuilds
    inputs.nixos-modules.nixosModules.users.chrisMinimal
    inputs.nixos-modules.nixosModules.homeAssistant
    inputs.nixos-hardware.nixosModules.system76
    ./hardware.nix
  ];

  # calibre-web 0.6.27b0 declares requests < 2.33, while nixpkgs currently
  # provides requests 2.33.1. Relax the upstream runtime metadata until nixpkgs
  # carries a compatible package fix.
  nixpkgs.overlays = [
    (final: prev: {
      calibre-web = prev.calibre-web.overridePythonAttrs (old: {
        pythonRelaxDeps = (old.pythonRelaxDeps or []) ++ ["requests"];
      });
    })
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.hostName = "tom";
  networking.networkmanager.enable = false;
  time.timeZone = "America/New_York";
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = false;
  };
  system.stateVersion = "26.05";
  users.users.chris.extraGroups = ["calibre-web"];
  home-manager.users.chris = {...}: {
    home.stateVersion = "26.05";
    dotfiles.shell.enable = false;
    dotfiles.gpg.enable = false;
  };

  # Passwordless sudo for deploy-rs
  dotfiles.sudoNoPassword.enable = true;

  dotfiles.selfDeploy = {
    enable = true;
    unitCheckTimeoutSec = 300;
    requiredSystemUnits = [
      "sshd.service"
      "tailscaled.service"
      "nix-daemon.service"
      "home-assistant.service"
      "postgresql.service"
      "calibre-web.service"
    ];
    timer = {
      onBootSec = "90m";
      onUnitActiveSec = "6h";
      randomizedDelaySec = "30m";
    };
  };

  services.calibre-web = {
    enable = true;

    openFirewall = true;
    listen.ip = "0.0.0.0";
    options.enableBookConversion = false;
    options.enableBookUploading = true;
  };
}
