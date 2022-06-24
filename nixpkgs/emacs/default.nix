{
  pkgs,
  config,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  pkgs-markdownMode = with pkgs; [
    mdl
    pandoc
    proselint
    python310Packages.grip
  ];

  pkgs-pythonMode = with pkgs.python310Packages; [
    black
    isort
    pyflakes
    pkgs.nodePackages.pyright
  ];

  pkgs-shellMode = with pkgs; [
    shellcheck
  ];

  pkgs-misc = with pkgs; [
    (aspellWithDicts (dicts: with dicts; [en en-computers en-science]))
    fd
    ripgrep
    sqlite
    wordnet
  ];
in {
  config.home.packages = pkgs-markdownMode ++ pkgs-pythonMode ++ pkgs-shellMode ++ pkgs-misc;

  config.programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  config.programs.doom-emacs = with pkgs; {
    enable = true;
    doomPrivateDir = ./doom.d;
    extraConfig = ''
      (setq
          mu4e-mu-binary "${mu}/bin/mu"
          sendmail-program "${msmtp}/bin/msmtp"
          message-sendmail-f-is-evil t
          message-sendmail-extra-arguments '("--read-envelope-from")
          message-send-mail-function 'message-send-mail-with-sendmail)
    '';
    extraPackages = [emacs-all-the-icons-fonts pkgs.mu];
    emacsPackage = emacsPgtkNativeComp;
  };

  # on macos nix-darwin handles the service configuration
  config.services.emacs.enable = isLinux;
  config.services.lorri.enable = isLinux;
}
