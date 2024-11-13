{dotfiles_lib, ...}: {
  imports = [
    ./gui
    ./meganz.nix
    ./shell.nix
    ./email.nix
  ];
  options.dotfiles = with dotfiles_lib.options; {
    enable = mkDefaultEnabledOption "enables the dotfiles home manager module.";
  };
}
