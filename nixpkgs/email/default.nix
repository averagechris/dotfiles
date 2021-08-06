{ pkgs, ... }:

let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
in
{
  home.packages = with pkgs; if isLinux then [ libsecret mu ] else [ ];

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
    };
  };

  services.mbsync = {
    enable = true;
    frequency = "*:0/10";
    postExec = "${pkgs.mu}/bin/mu index";
  };
}
