{ pkgs, config, ... }:

let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  pkgs-markdownMode = with pkgs; [
    mdl
    pandoc
    proselint
    python39Packages.grip
  ];

  pkgs-pythonMode = with pkgs.python39Packages; [
    black
    isort
    pkgs.poetry
    pyflakes
    pkgs.nodePackages.pyright
  ];

  pkgs-shellMode = with pkgs; [
    shellcheck
  ];

  pkgs-misc = with pkgs; [
    (aspellWithDicts (dicts: with dicts; [ en en-computers en-science ]))
    direnv
    fd
    ripgrep
    sqlite
    wordnet
  ];

in
{
  config.home.packages = pkgs-markdownMode ++ pkgs-pythonMode ++ pkgs-shellMode ++ pkgs-misc;

  config.programs.doom-emacs = {
    enable = true;
    doomPrivateDir = ./doom.d;
    extraConfig = ''
      (setq
          mu4e-mu-binary "${pkgs.mu}/bin/mu"
          sendmail-program "${pkgs.msmtp}/bin/msmtp"
          message-sendmail-f-is-evil t
          message-sendmail-extra-arguments '("--read-envelope-from")
          message-send-mail-function 'message-send-mail-with-sendmail)
    '';
    extraPackages = [ pkgs.emacs-all-the-icons-fonts pkgs.mu ];
  };

  # on macos nix-darwin handles the service configuration
  config.services.emacs.enable = isLinux;
  config.services.lorri.enable = isLinux;
}
