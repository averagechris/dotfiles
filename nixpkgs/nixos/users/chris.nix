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

  programs.gnupg.agent.enable = true;
  programs.gnupg.agent.pinentryFlavor = "curses";

  home-manager.users."chris" = {config, ...}: {
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
    config.programs.git.extraConfig.commit.gpgsign = true;
  };
}
