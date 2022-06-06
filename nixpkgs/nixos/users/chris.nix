{
  pkgs,
  inputs,
  ...
}: {
  imports = [./chris-minimal.nix];

  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  home-manager.users."chris" = {...}: {
    imports = [
      ../../emacs
      ../../firefox
      ../../guiapps
      ../../linux_desktop
      ../../meganz.nix
      ../../nerdfonts
      ../../sway
      ../../terminal_emulator
      inputs.nix-doom-emacs.hmModule
    ];
  };
}
