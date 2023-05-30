{
  pkgs,
  input-modules,
  sli-repo,
  lib,
  sshKeys,
  ...
}: let
  username = "chris";
  homeDirectory = "/home/${username}";
  sure = import ../../sure {inherit pkgs sli-repo;};
in {
  users.users = {
    "${username}" = {
      isNormalUser = true;
      extraGroups = [
        "docker"
        "networkmanager"
        "wheel"
      ];
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = lib.attrValues sshKeys.chris ++ ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ7FLKrbwo1hB9ThGrEcOP/pI05tA3vMuxaNH679BfZH chrisnotnix@suremac"];
    };
  };
  programs.zsh.enable = true;

  home-manager.users."${username}" = {pkgs, ...}: {
    home = {
      inherit username homeDirectory;
      stateVersion = "22.11";
    };

    programs.git = {
      userName = "Chris Cummings";
      userEmail = "chris.cummings@sureapp.com";
    };

    imports = [
      ../../emacs
      ../../git
      ../../firefox
      ../../neovim
      ../../shell
      ../../terminal_emulator
      ../../tmux
      ../../linux_desktop
      ../../zellij
      ../../helix.nix
      input-modules.doom
      # sure
    ];

    programs.git.extraConfig.commit.gpgsign = false; # TODO move gpg key over and use

    xdg.systemDirs.data = [
      "/usr/share"
      "/var/lib/flatpak/exports/share"
      "${homeDirectory}/.local/share/flatpak/exports/share"
    ];
  };

  programs.gnupg.agent.enable = true;
  programs.gnupg.agent.pinentryFlavor = "gnome3";

  security.sudo = {
    wheelNeedsPassword = false;
    execWheelOnly = true;
  };
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = false;
  };
}
