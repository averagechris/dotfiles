{
  pkgs,
  lib,
  sshKeys,
  ...
}: let
  username = "chris";
  homeDirectory = "/home/${username}";
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
    programs.git.extraConfig.commit.gpgsign = false; # TODO move gpg key over and use

    imports = [
      ../../../hm_modules
      ../../sure
    ];

    dotfiles.shell.python.enable = true;
    dotfiles.gui.enable = true;
    dotfiles.gui.sway.enable = false;

    programs.darktable.enable = false;
    programs.signal.enable = false;
    programs.write-stylus.enable = false;
    programs.zoom.enable = false;
  };

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
