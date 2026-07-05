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
  "openrouter-api-key.age".publicKeys = all-keys;
  "circleci-token.age".publicKeys = all-keys;
  "gpg-private-key.age".publicKeys = all-keys;
  "gpg-key-id.age".publicKeys = all-keys;
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

  # Trainwreck secrets (clawdbot)
  "trainwreck/telegram-bot-token.age".publicKeys = trainwreck-keys ++ systems-keys;
  "trainwreck/telegram-bot-token-staging.age".publicKeys = trainwreck-keys ++ systems-keys;
  "trainwreck/telegram-user-ids.age".publicKeys = trainwreck-keys ++ systems-keys;
  "trainwreck/openrouter-api-key.age".publicKeys = trainwreck-keys ++ systems-keys;
  "trainwreck/kagi-api-token.age".publicKeys = trainwreck-keys ++ systems-keys;
  "trainwreck/gateway-auth-token.age".publicKeys = trainwreck-keys ++ systems-keys;
  "trainwreck/imgflip-username.age".publicKeys = trainwreck-keys ++ systems-keys;
  "trainwreck/imgflip-password.age".publicKeys = trainwreck-keys ++ systems-keys;

  # Grem personality documents (contain personal info)
  "trainwreck/grem-AGENTS.md.age".publicKeys = trainwreck-keys ++ systems-keys ++ [suremac-key];
  "trainwreck/grem-SOUL.md.age".publicKeys = trainwreck-keys ++ systems-keys ++ [suremac-key];
  "trainwreck/grem-TOOLS.md.age".publicKeys = trainwreck-keys ++ systems-keys ++ [suremac-key];

  # Mira personality documents (Grem's baby sister)
  "trainwreck/mira-AGENTS.md.age".publicKeys = trainwreck-keys ++ systems-keys ++ [suremac-key];
  "trainwreck/mira-SOUL.md.age".publicKeys = trainwreck-keys ++ systems-keys ++ [suremac-key];
  "trainwreck/mira-TOOLS.md.age".publicKeys = trainwreck-keys ++ systems-keys ++ [suremac-key];

  # Mira Telegram bot tokens
  "trainwreck/telegram-bot-token-mira.age".publicKeys = trainwreck-keys ++ systems-keys;
  "trainwreck/telegram-bot-token-mira-staging.age".publicKeys = trainwreck-keys ++ systems-keys;

  # Identity links for session sharing across platforms (contains phone numbers)
  "trainwreck/identity-links.age".publicKeys = trainwreck-keys ++ systems-keys ++ [suremac-key];

  # Signal provider config (contains phone numbers - bot account and allowlist)
  "trainwreck/signal-config.age".publicKeys = trainwreck-keys ++ systems-keys ++ [suremac-key];
}
