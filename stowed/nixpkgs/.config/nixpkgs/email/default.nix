{ pkgs, ... }:

let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
in
{
  home.packages = with pkgs; if isLinux then [ libsecret mu ] else [ ];

  accounts.email.accounts = {
    # add a new email account by adding a nix module, then adding it to the .gitignore
    # or ignore privately
    # see example-email.nix for an example
    # e.g.:
    # example = import ./example-email.nix;
    personal = import ./personal.nix;
    icloud = import ./icloud.nix;
    sure = import ./sure.nix;
  };

  programs.mu.enable = true;
  programs.msmtp.enable = true;
  programs.mbsync = {
    enable = true;
    extraConfig = ''
      CopyArrivalDate yes
    '';
    groups = {
      personal-inboxes = {
        personal = [ ];
        icloud = [ ];
      };
      work = {
        sure = [ "[Gmail]/Inbox" ];
      };
    };
  };

  services.mbsync = {
    enable = true;
    frequency = "*:0/10";
    postExec = "${pkgs.mu}/bin/mu index";
  };
}
