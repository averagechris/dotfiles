{
  config,
  pkgs,
  input-modules,
  ...
}: {
  imports = [./chris-minimal.nix];

  config.programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  config.programs.gnupg.agent.enable = true;
  config.programs.gnupg.agent.pinentryFlavor = "gtk2";

  config.age.secrets.fastmail_password = {
    file = ../../../secrets/fastmail_password.age;
    group = "users";
    owner = "chris";
  };

  config.home-manager.users."chris" = {...}: {
    _module.args = {inherit (config.age) secrets;};
    imports = [
      ../../email
      ../../emacs
      ../../firefox
      ../../guiapps
      ../../linux_desktop
      ../../meganz.nix
      ../../nerdfonts
      ../../sway
      ../../terminal_emulator
      input-modules.doom
    ];
    programs.git.extraConfig.commit.gpgsign = true;

    home.pointerCursor = {
      name = "Adwaita";
      package = pkgs.gnome.adwaita-icon-theme;
      size = 14;
      x11 = {
        enable = false;
        defaultCursor = "Adwaita";
      };
    };
  };
}
