{dotfiles_lib, ...}: {
  imports = [
    ./agent-skills.nix
    ./gui
    ./gander.nix
    ./gpg.nix
    ./granola.nix
    ./linear-cli
    ./nitter-link.nix
    ./rdny.nix
    ./srht.nix
    ./sideshow.nix
    ./meganz.nix
    ./pi.nix
    ./dev-cache.nix
    ./shell.nix
    ./opencode
    ./opencode/session-cleanup.nix
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
