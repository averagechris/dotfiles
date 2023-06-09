{
  config,
  dotfiles_lib,
  input-modules,
  lib,
  ...
}: let
  cfg = config.dotiles;
in {
  imports = [
    input-modules.doom
    ./gui
    ./meganz.nix
    ./shell.nix
    ./email.nix
  ];
  options.dotfiles = with dotfiles_lib.options; {
    enable = mkDefaultEnabledOption "enables the dotfiles home manager module.";
  };
}
