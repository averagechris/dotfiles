{dotfiles_lib, ...}: {
  imports = [
    ./gui
    ./gander.nix
    ./gpg.nix
    ./granola.nix
    ./meganz.nix
    ./pi.nix
    ./shell.nix
    ./opencode
    ./helix
    ./helix-terminal-tools
    ./cosmic-workstation.nix
    ./hyprland-workstation.nix
    ./openclaw-fix.nix
  ];
  options.dotfiles = with dotfiles_lib.options; {
    enable = mkDefaultEnabledOption "enables the dotfiles home manager module.";
  };
}
