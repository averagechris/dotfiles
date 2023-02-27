{
  pkgs,
  input-modules,
  sli-repo,
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
    };
  };

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
      input-modules.doom
      sure
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
}
