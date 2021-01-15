{ pkgs, ...}:

let
  emailAttributes = email: {
    address = email;
    userName = email;
    passwordCommand = "${pkgs.gnome3.libsecret}/bin/secret-tool lookup email ${email}";

    msmtp.enable = true;

    mbsync = {
      enable = true;
      create = "both";
      expunge = "both";
      remove = "both";
      extraConfig.account = {
        # NOTE microsoft office 365 imap servers may require this to be 1
        # because they do not support concurrent imap commands
        PipelineDepth = 50;
      };

    };

  };
in {
  home.packages = with pkgs; [
    libsecret
    mu
  ];

  accounts.email.accounts = {
    chris-thesogu = (emailAttributes "chris@thesogu.com") // {
      primary = true;
      realName = "Chris Cummings";
      imap.host = "imap.fastmail.com";
      smtp.host = "smtp.fastmail.com";
    };
  };

  programs.msmtp.enable = true;
  programs.mbsync = {
    enable = true;
    extraConfig = ''
      CopyArrivalDate yes
    '';
  };

  services.mbsync = {
    enable = true;
    frequency = "*:0/10";
    postExec = "${pkgs.mu}/bin/mu index";
  };
}
