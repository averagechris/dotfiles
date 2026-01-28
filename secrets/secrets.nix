let
  systems-keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDOiCjIMganzY45qiHFEO2NqkXz2mWsSEmq3zIoRJsiA root@nixos" # nixos-thelio
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAy30vzaxmqc08+NcYYA7LflDqoZNdRoyVXVJ2H9p2Xp root@xps-nixos" # nixos-xps
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBNAyh1GNkiHi8eButk+acXT8E4LiKaLWq0jmJmQjwsk root@trap"
  ];

  trainwreck-key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICxXGUQ9Ey9/ndUJgr8ClI3PcnWYNnaY4kUMyHRrsYma root@trainwreck";

  trainwreck-keys = [trainwreck-key];
in {
  "fastmail_password.age".publicKeys = systems-keys;
  "fastmail_primary_address.age".publicKeys = systems-keys;

  # Trainwreck secrets (clawdbot)
  "trainwreck/telegram-bot-token.age".publicKeys = trainwreck-keys ++ systems-keys;
  "trainwreck/telegram-user-ids.age".publicKeys = trainwreck-keys ++ systems-keys;
  "trainwreck/openrouter-api-key.age".publicKeys = trainwreck-keys ++ systems-keys;
  "trainwreck/kagi-api-token.age".publicKeys = trainwreck-keys ++ systems-keys;
}
