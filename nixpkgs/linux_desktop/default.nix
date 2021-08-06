{ config, pgks, ... }:

{
  config.home.sessionVariables = {
    BROSWER = "firefox";
  };

  config.pam.sessionVariables = config.home.sessionVariables // {
    LANGUAGE = "en_US:en";
    LANG = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_ADDRESS = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    PAPERSIZE = "letter";
  };

  # allows Gnome to find the gui applications
  config.targets.genericLinux.enable = true;
  config.xdg.enable = true;
  config.xdg.mime.enable = true;

  # make sure all of the distro's default XDG_DATA_DIRS values are in here
  config.xdg.systemDirs.data = [
    "/usr/local/share"
    "/usr/share"
    "${config.home.homeDirectory}/.nix-profile/share"
    "${config.home.homeDirectory}/.nix-profile/share/applications"
    "${config.home.homeDirectory}/local/share/flatpak/exports/share"

    # "/usr/share/pop"
    # "/var/lib/flatpak/exports/share"
  ];
}
