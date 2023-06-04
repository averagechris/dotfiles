{
  pkgs,
  lib,
  config,
  ...
}: let
  formatter = pkgs.writeShellApplication {
    name = "alejandra_doom_formatter";
    runtimeInputs = [pkgs.alejandra];
    text = "alejandra --quiet";
  };
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
    nodePackages.bash-language-server
  ];
  pkgs-misc = with pkgs; [
    (aspellWithDicts (dicts: with dicts; [en en-computers en-science]))
    fd
    ripgrep
    sqlite
    wordnet
    nodePackages.yaml-language-server
  ];
in {
  config.home.packages = lib.mkIf config.dotfiles.shell.emacs.enable (pkgs-markdownMode ++ pkgs-pythonMode ++ pkgs-shellMode ++ pkgs-misc);

  config.programs.doom-emacs = with pkgs; {
    doomPrivateDir = ./doom.d;
    extraConfig = ''
      (after! mu4e (setq
          mu4e-mu-binary "${mu}/bin/mu"
          sendmail-program "${msmtp}/bin/msmtp"
          message-sendmail-f-is-evil t
          message-sendmail-extra-arguments '("--read-envelope-from")
          message-send-mail-function 'message-send-mail-with-sendmail))

      (after! nix-mode (setq nix-nixfmt-bin "${formatter}/bin/alejandra_doom_formatter"))
    '';
    extraPackages = [emacs-all-the-icons-fonts mu];
    emacsPackage = emacsPgtk;
  };
}
