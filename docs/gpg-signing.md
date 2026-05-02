# GPG Signing for Git and Jujutsu

This document describes the automatic GPG signing setup for git and jj (jujutsu) commits using agenix for secret management.

## Overview

The dotfiles repository includes an automated GPG signing configuration that:
- Stores your GPG private key securely with agenix
- Automatically imports the key during system rebuilds
- Configures both git and jj to sign commits with your GPG key
- Works across all machines (tater, suremac, trap, thorny, cruber, trainwreck)
- Passphrase caching for 7 days (no need to enter passphrase for every commit)

## Architecture

### Components

1. **Agenix Secret** (`secrets/gpg-private-key.age`)
   - Stores your GPG private key in encrypted form
   - Accessible to all machines via SSH keys
   - Decrypted to `/run/agenix/gpg-private-key` at runtime

2. **GPG Module** (`flakes/hm-modules/modules/gpg.nix`)
   - Imports the GPG key during home-manager activation
   - Configures git and jj with the signing key from agenix secrets
   - Sets `GPG_TTY` for proper pinentry functionality
   - Enables GPG agent with 7-day passphrase cache

3. **Git Configuration**
   - Signing key is written by activation from `/run/agenix/gpg-key-id`
   - Commits are signed by default (`commit.gpgsign = true`)

4. **Jujutsu Configuration**
   - Signing key is written by activation from `/run/agenix/gpg-key-id`
   - Uses GPG backend for signing

5. **GPG Agent** (NixOS configuration)
   - Configured in `flakes/nixos-modules/modules/users/chris.nix`
   - Uses pinentry-qt for graphical passphrase prompts
   - **7-day cache TTL (604800 seconds)** - enter passphrase once, cached for a week
   - 1-year max cache TTL (31536000 seconds)

6. **GPG Cleanup Service** (home-manager)
   - Automatically runs on login via `graphical-session.target`
   - Kills stale `keyboxd` processes that hold locks after reboot
   - Restarts `gpg-agent` to ensure clean state
   - Configured in `flakes/hm-modules/modules/gpg.nix`

## Setup Instructions

### Initial Setup (One-time)

1. **Get your GPG key ID**:
   ```bash
   gpg --list-secret-keys --keyid-format LONG
   ```
   Look for the line starting with `sec` and copy the key ID (e.g., `623745A83D6C9C02`)

2. **Export your GPG private key**:
   ```bash
   # Replace YOUR_KEY_ID with the ID from step 1
   gpg --export-secret-key --armor YOUR_KEY_ID > ~/private-key.asc
   ```

3. **Create the agenix secrets**:
   ```bash
   cd ~/dotfiles/secrets
   ./recreate-secrets.sh
   ```
   - Use fzf to select both `gpg-private-key.age` and `gpg-key-id.age`
   - For `gpg-private-key.age`: paste your entire GPG private key (including BEGIN/END lines)
   - For `gpg-key-id.age`: paste just the key ID (e.g., `623745A83D6C9C02`)
   - Save and close each editor

4. **Configure your host** (example for tater):
   ```nix
   # In flakes/hosts/tater/configuration.nix
   age.secrets.gpg-private-key = {
     file = ../../../secrets/gpg-private-key.age;
     owner = "chris";
     group = "users";
     mode = "0400";
   };
   age.secrets.gpg-key-id = {
     file = ../../../secrets/gpg-key-id.age;
     owner = "chris";
     group = "users";
     mode = "0400";
   };
   
   home-manager.users.chris = {
     dotfiles.gpg.enable = true;
   };
   ```
   The base-lib host helpers automatically pass `secrets = config.age.secrets`
   into home-manager, so no manual `_module.args` wiring is needed.

5. **Deploy the configuration**:
   ```bash
   sudo nixos-rebuild switch --flake ./flakes/hosts/tater#tater
   ```

### Adding to a New Machine

To add GPG signing to a new machine:

1. Ensure the machine's SSH key is in `secrets/secrets.nix` under `all-keys`
2. Add both agenix secrets to the host's `configuration.nix`:
   ```nix
   age.secrets.gpg-private-key = { ... };
   age.secrets.gpg-key-id = { ... };
   ```
3. Enable the GPG module: `dotfiles.gpg.enable = true`
4. Rebuild the system

## How It Works

### During System Rebuild

1. Agenix decrypts secrets to `/run/agenix/`
   - `gpg-private-key.age` → `/run/agenix/gpg-private-key`
   - `gpg-key-id.age` → `/run/agenix/gpg-key-id`
2. Home-manager activation runs the `import-gpg-key` script
3. The script imports the GPG private key into the user's keyring
4. The `configure-signing-key` script reads the key ID from `/run/agenix/gpg-key-id`
5. It configures git: `git config --global user.signingkey $KEY_ID`
6. It configures jj: `jj config set --user user.signing-key $KEY_ID`
7. The GPG agent is started with 7-day passphrase cache

### During Normal Operation

- Git automatically signs all commits with the configured key
- Jujutsu automatically signs all commits with the same key
- **GPG agent caches the passphrase for 7 days** - you only need to enter it once per week
- The key persists in the GPG keyring across rebuilds
- The key ID is read from agenix on each rebuild
- Profile switches should preserve the in-memory passphrase cache; the automatic cleanup service avoids killing `gpg-agent` because that daemon owns the cache.

### Passphrase Caching

The GPG agent is configured with:
- `default-cache-ttl` = 604800 seconds (7 days)
- `max-cache-ttl` = 31536000 seconds (1 year)

This means:
- After entering your passphrase once, it's cached for 7 days
- Each time you use it, the 7-day timer resets
- Maximum cache time is 1 year
- You can change these values in `flakes/nixos-modules/modules/users/chris.nix`

Unlike macOS Keychain, this setup does not persist the GPG passphrase itself to disk. On Linux, the normal GPG model is an in-memory `gpg-agent` cache. The dotfiles optimize for keeping that agent alive across rebuilds/profile switches while still providing a manual recovery command for the rare stale-lock case.

To test the caching:
```bash
# After entering your passphrase for the first commit:
git commit -m "First commit"  # Will prompt for passphrase

# Subsequent commits within 7 days:
git commit -m "Second commit"  # Will NOT prompt for passphrase
```

## Troubleshooting

### GPG Agent Lock / Timeout

If you see "waiting for lock" errors or timeouts when signing with jj or git:

**Cause**: Stale `keyboxd` process holding a lock after reboot

**Solution**: See [GPG Agent Lock Troubleshooting Guide](../troubleshooting/gpg-agent-lock.md)

The dotfiles include an automatic cleanup service that kills stale `keyboxd` processes on login without killing `gpg-agent`, preserving the passphrase cache across profile switches.

If the cleanup service is failing, check:

```bash
systemctl --user --no-pager --full status gpg-agent-cleanup.service
```

If the status shows an `EXEC` failure for `pkill`, rebuild and switch your system or Home Manager configuration so the updated cleanup unit is installed.

If GPG is still wedged and you are willing to lose the current passphrase cache, run:

```bash
gpg-agent-recover
```

This kills stale `keyboxd`, restarts `gpg-agent`, and relaunches it. Your next signing operation will prompt for the passphrase again.

### "No secret key" Error

If you see this error when committing:
```
error: gpg failed to sign the data
fatal: failed to write commit object
```

**Cause**: The GPG key wasn't imported properly

**Solution**:
1. Check if the secret file exists: `ls -la /run/agenix/gpg-private-key`
2. Check if the key was imported: `gpg --list-secret-keys --keyid-format LONG`
3. Check home-manager activation logs: `journalctl --user -u home-manager-chris.service`
4. Manually import the key: `gpg --import /run/agenix/gpg-private-key`

### Pinentry Not Working

If GPG prompts don't appear:

**Cause**: `GPG_TTY` not set or GPG agent not running

**Solution**:
1. Ensure `dotfiles.gpg.enable = true` is set
2. Check GPG agent status: `gpg-agent --daemon`
3. Test pinentry: `echo "test" | gpg --clearsign`

### Key ID Changes

If you generate a new GPG key:

**Solution**:
1. Export the new private key: `gpg --export-secret-key --armor NEW_KEY_ID > new-key.asc`
2. Update both agenix secrets: `cd ~/dotfiles/secrets && ./recreate-secrets.sh`
   - Update `gpg-private-key.age` with the new private key
   - Update `gpg-key-id.age` with the new key ID
3. Rebuild: `sudo nixos-rebuild switch --flake ./flakes/hosts/<hostname>#<hostname>`

## Security Considerations

- The GPG private key is encrypted with agenix and only decrypted at runtime
- The decrypted key exists only at `/run/agenix/gpg-private-key` (tmpfs, not persisted to disk)
- The key is imported into the GPG keyring but the keyring is protected by standard GPG permissions
- Always use `gpg --export-secret-key --armor` to export keys (never share the binary format)
- The agenix secret is accessible to all machines defined in `secrets/secrets.nix`

## Related Files

- `secrets/secrets.nix` - Defines which machines can access the GPG secrets
- `secrets/recreate-secrets.sh` - Interactive script to create/update secrets
- `secrets/gpg-private-key.age` - Encrypted GPG private key
- `secrets/gpg-key-id.age` - Encrypted GPG key ID
- `flakes/hm-modules/modules/gpg.nix` - Main GPG module with activation scripts
- `flakes/hm-modules/modules/git/default.nix` - Git configuration
- `flakes/hm-modules/modules/jujutsu/default.nix` - Jujutsu configuration
- `flakes/nixos-modules/modules/users/chris.nix` - GPG agent configuration

## Future Improvements

- [ ] Add support for multiple GPG keys
- [ ] Create a wrapper script to rotate GPG keys
- [ ] Add verification step to ensure key matches expected fingerprint
- [ ] Support for hardware security keys (YubiKey, etc.)
