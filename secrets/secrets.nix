let
  systems-keys = [
    # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDOiCjIMganzY45qiHFEO2NqkXz2mWsSEmq3zIoRJsiA root@nixos"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAy30vzaxmqc08+NcYYA7LflDqoZNdRoyVXVJ2H9p2Xp root@xps-nixos" # nixos-xps
  ];
in {
  "fastmail_password.age".publicKeys = systems-keys;
  "fastmail_primary_address.age".publicKeys = systems-keys;
}
