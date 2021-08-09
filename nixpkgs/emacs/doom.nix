{ pkgs }:

pkgs.callPackage
  (builtins.fetchTarball {
    url = "https://github.com/vlaci/nix-doom-emacs/archive/master.tar.gz";
  })
{
  doomPrivateDir = ./doom.d;
  extraConfig = ''
    (setq
        mu4e-mu-binary "${pkgs.mu}/bin/mu"
        sendmail-program "${pkgs.msmtp}/bin/msmtp"
        message-sendmail-f-is-evil t
        message-sendmail-extra-arguments '("--read-envelope-from")
        message-send-mail-function 'message-send-mail-with-sendmail)
  '';
  extraPackages = epkgs: [ pkgs.emacs-all-the-icons-fonts pkgs.mu epkgs.vterm ];
  # TODO on macos we should pass pkgs.emacsMacPort here but it's currently broken
  # FIXME upstream a change with attr overrides breaks due to a missing attribute `passthru`
  emacsPackages = pkgs.emacsPackagesFor pkgs.emacs;
}
