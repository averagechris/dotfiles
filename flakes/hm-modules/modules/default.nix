{dotfiles_lib, ...}: {
  imports = [
    ./gui
    ./gander.nix
    ./gpg.nix
    ./granola.nix
    ./linear-cli
    ./srht.nix
    ./sideshow.nix
    ./meganz.nix
    ./pi.nix
    ./dev-cache.nix
    ./shell.nix
    ./opencode
    ./helix
    ./helix-terminal-tools
    ./cosmic-workstation.nix
    ./ctx.nix
    ./hyprland-workstation.nix
  ];
  options.dotfiles = with dotfiles_lib.options; {
    enable = mkDefaultEnabledOption "enables the dotfiles home manager module.";
  };
}
