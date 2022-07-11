let
  chris-thelio = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDOiCjIMganzY45qiHFEO2NqkXz2mWsSEmq3zIoRJsiA root@nixos";
in {
  "fastmail_password.age".publicKeys = [chris-thelio];
  "fastmail_primary_address.age".publicKeys = [chris-thelio];
}
