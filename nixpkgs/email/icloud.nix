let
  template = import ./template.nix;
in
(template {
  email = "mistahchris@mac.com";
  realName = "Chris Cummings";
  imapHost = "imap.mail.me.com";
  smtpHost = "smtp.mail.me.com";
})
