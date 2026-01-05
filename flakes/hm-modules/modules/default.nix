{dotfiles_lib, ...}: {
  imports = [
    ./gui
    ./meganz.nix
    ./shell.nix
    ./opencode.nix
    ./email.nix
    ./helix.nix
    ./helix-terminal-tools
  ];
  options.dotfiles = with dotfiles_lib.options; {
    enable = mkDefaultEnabledOption "enables the dotfiles home manager module.";
  };
}
