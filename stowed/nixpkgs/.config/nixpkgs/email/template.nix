let pkgs = import <nixpkgs> { };
in { email, realName, imapHost, smtpHost, gmail ? false }: {
  flavor = if gmail then "gmail.com" else "plain";
  address = email;
  userName = email;
  realName = realName;

  passwordCommand =
    if pkgs.stdenv.hostPlatform.isLinux then
      "${pkgs.gnome3.libsecret}/bin/secret-tool lookup email ${email}"
    else
      "security find-generic-password -a christophercummings -s ${email} -w";

  imap.host = imapHost;
  smtp.host = smtpHost;

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

}
