{
  inputs,
  pkgs,
  config,
  lib,
  ...
}: {
  imports = [
    inputs.nixos-modules.nixosModules.common
    inputs.nixos-modules.nixosModules.tailscale
    inputs.nixos-modules.nixosModules.sudoDeploy
    inputs.nixos-modules.nixosModules.users.chrisMinimal
    inputs.nixos-modules.nixosModules.isRemoteBuilder
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

  # Agenix secrets
  age.secrets = {
    telegram-bot-token = {
      file = ../../../secrets/trainwreck/telegram-bot-token.age;
      owner = "chris";
      group = "users";
      mode = "0400";
    };
    telegram-user-ids = {
      file = ../../../secrets/trainwreck/telegram-user-ids.age;
      owner = "chris";
      group = "users";
      mode = "0400";
    };
    openrouter-api-key = {
      file = ../../../secrets/trainwreck/openrouter-api-key.age;
      owner = "chris";
      group = "users";
      mode = "0400";
    };
    kagi-api-token = {
      file = ../../../secrets/trainwreck/kagi-api-token.age;
      owner = "chris";
      group = "users";
      mode = "0400";
    };
    gateway-auth-token = {
      file = ../../../secrets/trainwreck/gateway-auth-token.age;
      owner = "chris";
      group = "users";
      mode = "0400";
    };
  };

  # System packages
  environment.systemPackages = with pkgs; [
    htop
    tmux
    curl
    jq
  ];

  system.stateVersion = "24.11";

  # Home Manager configuration for chris
  home-manager.users.chris = {pkgs, ...}: {
    home.stateVersion = "24.11";

    imports = [
      inputs.hm-modules.homeManagerModules.default
      inputs.nix-clawdbot.homeManagerModules.moltbot
    ];

    # Moltbot configuration
    programs.moltbot = {
      documents = ./clawdbot-documents;
      gateway.authTokenFile = config.age.secrets.gateway-auth-token.path;
      firstParty = {
        # Disabled: nix-steipete-tools has corrupted store paths locally
        summarize.enable = false;
        oracle.enable = false;
        # Disabled: no screen on headless server
        peekaboo.enable = false;
      };
      instances.default = {
        enable = true;
        agent.model = "openrouter/anthropic/claude-sonnet-4";
        providers.openrouter.apiKeyFile = config.age.secrets.openrouter-api-key.path;
        providers.telegram = {
          enable = true;
          botTokenFile = config.age.secrets.telegram-bot-token.path;
          allowFromFile = config.age.secrets.telegram-user-ids.path;
        };
        systemd.enable = true;
        launchd.enable = false;
      };
    };

    # Minimal shell setup for server
    dotfiles.shell = {
      enable = true;
      shell_scripts.enable = false;
      pipx.enable = false;
      gpg.enable = false;
    };

    # Disable programs that require flake inputs not available on this host
    programs.helix.enable = lib.mkForce false;

    # Enable jj and opencode
    programs.jujutsu.enable = true;
    programs.opencode.enable = true;
  };
}
