let
  template = import ./template.nix;
in
(template {
  email = "chris@thesogu.com";
  realName = "Chris Cummings";
  imapHost = "imap.fastmail.com";
  smtpHost = "smtp.fastmail.com";
}) // {
  primary = true;
}
