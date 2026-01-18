{dotfiles_lib, ...}: {
  imports = [
    ./gui
    ./meganz.nix
    ./shell.nix
    ./opencode
    ./helix
    ./helix-terminal-tools
    ./cosmic-workstation.nix
  ];
  options.dotfiles = with dotfiles_lib.options; {
    enable = mkDefaultEnabledOption "enables the dotfiles home manager module.";
  };
}
