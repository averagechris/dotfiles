let
  template = import ./template.nix;
in
(template "email@email.domain" "Real Name" "imap.email.domain" "smtp.email.domain") // {
  # you can pass extra params here if necessary. otherwise omit the `// { ... }`
  primary = true;
}
