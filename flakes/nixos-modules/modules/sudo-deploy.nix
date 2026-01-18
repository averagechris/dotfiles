{
  lib,
  config,
  ...
}: {
  options.dotfiles.sudoNoPassword = {
    enable = lib.mkEnableOption "passwordless sudo for wheel group (for deployable hosts)";
  };

  config = lib.mkIf config.dotfiles.sudoNoPassword.enable {
    security.sudo = {
      wheelNeedsPassword = false;
      execWheelOnly = true;
    };
  };
}
