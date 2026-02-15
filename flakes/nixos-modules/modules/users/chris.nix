{
  config,
  pkgs,
  ...
}: {
  imports = [./chris-minimal.nix];

  config.programs.sway = {
    enable = false;
    wrapperFeatures.gtk = true;
  };

  config.programs.gnupg.agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-qt;
    settings = {
      "default-cache-ttl" = 604800;
      "max-cache-ttl" = 31536000;
      # Prevent keyboxd hangs by setting a timeout for database operations
      "scd-event-verbose" = 0;
      "gnupg" = "${pkgs.gnupg}";
    };
  };

  config.age.secrets.fastmail_password = {
    file = ../../../../secrets/fastmail_password.age;
    group = "users";
    owner = "chris";
  };

  config.home-manager.users."chris" = {...}: {
    _module.args = {inherit (config.age) secrets;};
    programs.git.settings.commit.gpgsign = true;
    programs.nushell.enable = true;
  };
}
