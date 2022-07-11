{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [./chris-minimal.nix];

  config.programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  config.programs.gnupg.agent.enable = true;
  config.programs.gnupg.agent.pinentryFlavor = "curses";

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
      inputs.nix-doom-emacs.hmModule
    ];
    programs.git.extraConfig.commit.gpgsign = true;
  };
}
