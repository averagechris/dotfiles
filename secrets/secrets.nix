let
  systems-keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDOiCjIMganzY45qiHFEO2NqkXz2mWsSEmq3zIoRJsiA root@nixos" # nixos-thelio
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAy30vzaxmqc08+NcYYA7LflDqoZNdRoyVXVJ2H9p2Xp root@xps-nixos" # nixos-xps
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBNAyh1GNkiHi8eButk+acXT8E4LiKaLWq0jmJmQjwsk root@trap"
  ];

  trainwreck-key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICxXGUQ9Ey9/ndUJgr8ClI3PcnWYNnaY4kUMyHRrsYma root@trainwreck";
  suremac-key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILz1u19VoCC/jj2lL34CmHwKAtIGt2clyMbZU8Cz4q14 chris.cummings@sureapp.com";
  tater-key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBq8+MKDCaI81h80Q0xqch/jnJLaScTjpy0/LfpNQerv root@tater";

  trainwreck-keys = [trainwreck-key];

  # All keys that should have access to shared secrets (openrouter, etc.)
  all-keys = systems-keys ++ trainwreck-keys ++ [suremac-key tater-key];

  # Systems keys plus tater for fastmail access
  systems-keys-plus-tater = systems-keys ++ [tater-key];
in {
  "fastmail_password.age".publicKeys = systems-keys-plus-tater;
  "fastmail_primary_address.age".publicKeys = systems-keys-plus-tater;

  # Shared secrets (accessible from all machines)
  "circleci-token.age".publicKeys = all-keys;
  "gpg-private-key.age".publicKeys = all-keys;
  "gpg-key-id.age".publicKeys = all-keys;

  # OpenRouter API keys, split by account scope. The work key is readable
  # only by suremac; the personal key covers every other machine.
  "openrouter-api-key-work.age".publicKeys = [suremac-key];
  "openrouter-api-key-personal.age".publicKeys =
    systems-keys ++ trainwreck-keys ++ [tater-key];
  "granola-token.age".publicKeys = [suremac-key];
  "opencode-sure-stack-context.age".publicKeys = [suremac-key];

  # Thorny secrets (fleet-cache-warmer)
  # Cachix auth token with write access to the averagechris-dotfiles cache.
  # Ships as the literal placeholder REPLACE_ME until provisioned; the warmer
  # service skips itself while the placeholder is in place.
  "cachix-auth-token.age".publicKeys = systems-keys ++ [suremac-key];

  # Thorny secrets
  "thorny/hut-access-token.age".publicKeys = systems-keys ++ [suremac-key];

  # Hister: contains HISTER__SERVER__OAUTH__GITHUB__CLIENT_SECRET for the
  # GitHub OAuth app.
  "thorny/hister-env.age".publicKeys = systems-keys ++ [suremac-key];
}
