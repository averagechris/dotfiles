{dotfiles_lib, ...}: {
  imports = [
    ./gui
    ./meganz.nix
    ./shell.nix
    ./email.nix
    ./helix-yazi-integration
  ];
  options.dotfiles = with dotfiles_lib.options; {
    enable = mkDefaultEnabledOption "enables the dotfiles home manager module.";
  };
}
