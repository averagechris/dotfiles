{config, ...}: {
  imports = [./chris-minimal.nix];

  config.programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  config.programs.gnupg.agent.enable = true;
  config.programs.gnupg.agent.pinentryFlavor = "qt";

  config.age.secrets.fastmail_password = {
    file = ../../../secrets/fastmail_password.age;
    group = "users";
    owner = "chris";
  };

  config.home-manager.users."chris" = {...}: {
    _module.args = {inherit (config.age) secrets;};
    programs.git.extraConfig.commit.gpgsign = true;
    dotfiles.shell.nerdfonts.enable = true;
    programs.nushell.enable = true;
  };
}
