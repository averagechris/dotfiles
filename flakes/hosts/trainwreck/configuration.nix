{
  inputs,
  pkgs,
  config,
  ...
}: let
  nixosConfig = config;
  # Temporary native aarch64 build used to measure Thorny's binfmt/QEMU miss
  # path. Remove after the operational measurement is recorded.
  trainwreckQemuProbe = pkgs.runCommandCC "trainwreck-qemu-probe-2026-07-10" {} ''
    mkdir -p "$out/bin"
    cat >probe.c <<'EOF'
    #include <stdio.h>

    int main(void) {
      puts("trainwreck aarch64 QEMU probe: 2026-07-10");
      return 0;
    }
    EOF
    "$CC" -O2 -o "$out/bin/trainwreck-qemu-probe" probe.c
  '';
in {
  imports = [
    inputs.nixos-modules.nixosModules.common
    inputs.nixos-modules.nixosModules.tailscale
    inputs.nixos-modules.nixosModules.sudoDeploy
    inputs.nixos-modules.nixosModules.selfDeploy
    inputs.nixos-modules.nixosModules.users.chrisMinimal
    inputs.nixos-modules.nixosModules.isRemoteBuilder
    inputs.nixos-modules.nixosModules.useRemoteBuilds
    inputs.agenix.nixosModules.default
    inputs.disko.nixosModules.disko
    ./hardware.nix
    ./disko.nix
  ];

  # Boot configuration (systemd-boot for UEFI)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "trainwreck";
  networking.networkmanager.enable = false;

  # Timezone
  time.timeZone = "America/New_York";

  # SSH server
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = false;
  };

  # Passwordless sudo for deploy-rs
  dotfiles.sudoNoPassword.enable = true;

  dotfiles.selfDeploy = {
    enable = true;
    requiredSystemUnits = [
      "sshd.service"
      "tailscaled.service"
      "nix-daemon.service"
      "caddy.service"
    ];
    timer = {
      onBootSec = "120m";
      onUnitActiveSec = "6h";
      randomizedDelaySec = "30m";
    };
  };

  # Public front door for hister (the service and its data live on thorny).
  # Caddy terminates TLS here and reverse-proxies over the tailnet.
  # "thorny" resolves via Tailscale MagicDNS (nameserver 100.100.100.100 is
  # configured by the shared tailscale module); the tailnet's full MagicDNS
  # domain is not recorded in this repo, so the bare name is used.
  services.caddy = {
    enable = true;
    virtualHosts."hister.thesogu.com".extraConfig = ''
      reverse_proxy thorny:4433
    '';
  };
  networking.firewall.allowedTCPPorts = [80 443];

  # Agenix secrets
  age.secrets = {
    openrouter-api-key = {
      file = ../../../secrets/openrouter-api-key.age;
      owner = "chris";
      group = "users";
      mode = "0400";
    };
  };

  environment.systemPackages = with pkgs; [
    htop
    tmux
    curl
    jq
    trainwreckQemuProbe
  ];

  system.stateVersion = "26.05";

  # Home Manager configuration for chris
  home-manager.users.chris = {...}: {
    home.stateVersion = "26.05";

    imports = [inputs.hm-modules.homeManagerModules.default];

    # Keep the VPS profile narrow. The shared shell profile is workstation-oriented
    # and pulls in file-manager, media, and audio tooling that trainwreck does not
    # need for deploys, Caddy, self-deploy, or bot experimentation.
    dotfiles.shell.enable = false;
    dotfiles.gpg.enable = false;

    # Enable jj and opencode
    programs.jujutsu.enable = true;
    dotfiles.jujutsu.workflowAliases.enable = false;
    programs.opencode.enable = true;
    dotfiles.opencode.openrouterApiKeyFile = nixosConfig.age.secrets.openrouter-api-key.path;
    programs.starship.enable = false;
  };
}
