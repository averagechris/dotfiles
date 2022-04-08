{ pkgs, inputs, ... }:

{

  imports = [ ./chris-minimal.nix ];

  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  home-manager.users."chris" = { ... }: {

    imports = [
      ../../emacs
      ../../firefox
      ../../guiapps
      ../../linux_desktop
      ../../nerdfonts
      ../../personal_scripts
      ../../sway
      ../../terminal_emulator
      inputs.nix-doom-emacs.hmModule
    ];

  };
}
