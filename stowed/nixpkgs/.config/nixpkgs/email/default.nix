{ pkgs, ... }:

{
  home.packages = with pkgs; [
    libsecret
    mu
  ];

  accounts.email.accounts = {
    # add a new email account by adding a nix module, then adding it to the .gitignore
    # see example-email.nix for an example
    # e.g.:
    # example = import ./example-email.nix;
    personal = import ./personal.nix;
    icloud = import ./icloud.nix;
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
        personal = [];
        icloud = [];
      };
    };
  };

  services.mbsync = {
    enable = true;
    frequency = "*:0/10";
    postExec = "${pkgs.mu}/bin/mu index";
  };
}
