{
  pkgs,
  secrets,
  ...
}: let
  primaryAddress = "chris@thesogu.com";
in {
  home.packages = with pkgs; [mu];

  programs.mu.enable = true;
  programs.msmtp.enable = true;
  programs.mbsync = {
    enable = true;
    extraConfig = ''
      CopyArrivalDate yes
    '';
    groups = {
      personal-inboxes = {
        "${primaryAddress}" = [];
      };
    };
  };

  services.mbsync = {
    enable = true;
    frequency = "*:0/10";
    postExec = "${pkgs.mu}/bin/mu index";
  };

  # TODO create systemd oneshot job to run `mbsync --all`
  # and mu init
  # and mu index
  # so new systems are auto-setup
  # without having to run those commands manually
  accounts.email.accounts = {
    "${primaryAddress}" = {
      address = primaryAddress;
      userName = primaryAddress;
      realName = "Chris Cummings";
      primary = true;
      mbsync = {
        enable = true;
        create = "both";
        expunge = "both";
        remove = "both";
        extraConfig.account.PipelineDepth = 50;
      };
      msmtp.enable = true;
      imap.host = "imap.fastmail.com";
      smtp.host = "smtp.fastmail.com";
      passwordCommand = "cat ${secrets.fastmail_password.path}";
    };
  };
}
