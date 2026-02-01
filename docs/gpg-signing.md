# GPG Signing for Git and Jujutsu

This document describes the automatic GPG signing setup for git and jj (jujutsu) commits using agenix for secret management.

## Overview

The dotfiles repository includes an automated GPG signing configuration that:
- Stores your GPG private key securely with agenix
- Automatically imports the key during system rebuilds
- Configures both git and jj to sign commits with the imported key
- Works across all machines (tater, suremac, trap, thorny, cruber, trainwreck)

## Architecture

### Components

1. **Agenix Secret** (`secrets/gpg-private-key.age`)
   - Stores your GPG private key in encrypted form
   - Accessible to all machines via SSH keys
   - Decrypted to `/run/agenix/gpg-private-key` at runtime

2. **GPG Module** (`flakes/hm-modules/modules/gpg.nix`)
   - Imports the GPG key during home-manager activation
   - Automatically detects the key ID from the imported key
   - Configures git and jj to use the detected key
   - Sets `GPG_TTY` for proper pinentry functionality

3. **Git Module** (`flakes/hm-modules/modules/git/default.nix`)
   - Configures git to sign commits by default
   - Signing key is set dynamically by the GPG module
   - Avoids hardcoding the key ID in the configuration

4. **Jujutsu Module** (`flakes/hm-modules/modules/jujutsu/default.nix`)
   - Inherits the signing key from git configuration
   - Uses the same GPG key for signing jj commits
   - Configures GPG as the signing backend

5. **GPG Agent** (NixOS configuration)
   - Configured in `flakes/nixos-modules/modules/users/chris.nix`
   - Uses pinentry-qt for graphical passphrase prompts
   - 7-day cache TTL (604800 seconds) to reduce passphrase prompts
   - 1-year max cache TTL (31536000 seconds)

## Setup Instructions

### Initial Setup (One-time)

1. **Export your GPG private key** (if you haven't already):
   ```bash
   # Find your key ID
   gpg --list-secret-keys --keyid-format LONG
   
   # Export the private key (replace YOUR_KEY_ID)
   gpg --export-secret-key --armor YOUR_KEY_ID > ~/private-key.asc
   ```

2. **Create the agenix secret**:
   ```bash
   cd ~/dotfiles/secrets
   ./recreate-secrets.sh
   ```
   - Use fzf to select `gpg-private-key.age`
   - When the editor opens, paste your entire GPG private key
   - Include the `-----BEGIN PGP PRIVATE KEY BLOCK-----` and `-----END PGP PRIVATE KEY BLOCK-----` lines
   - Save and close the editor

3. **Configure your host** (example for tater):
   ```nix
   # In flakes/hosts/tater/configuration.nix
   age.secrets.gpg-private-key = {
     file = ../../../secrets/gpg-private-key.age;
     owner = "chris";
     group = "users";
     mode = "0400";
   };
   
   home-manager.users.chris = {config, lib, ...}: {
     _module.args = {gpgPrivateKeyPath = "/run/agenix/gpg-private-key"; };
     dotfiles.gpg.enable = true;
   };
   ```

4. **Deploy the configuration**:
   ```bash
   sudo nixos-rebuild switch --flake ./flakes/hosts/tater#tater
   ```

### Adding to a New Machine

To add GPG signing to a new machine:

1. Ensure the machine's SSH key is in `secrets/secrets.nix` under `all-keys`
2. Add the agenix secret configuration to the host's `configuration.nix`
3. Enable the GPG module with `dotfiles.gpg.enable = true`
4. Pass the secret path via `_module.args`
5. Rebuild the system

## How It Works

### During System Rebuild

1. Agenix decrypts `gpg-private-key.age` to `/run/agenix/gpg-private-key`
2. Home-manager activation runs the `import-gpg-key` script
3. The script imports the GPG private key into the user's keyring
4. The `configure-signing-keys` script runs after import
5. It extracts the key ID from the imported key
6. Configures git: `git config --global user.signingkey $KEY_ID`
7. Configures jj: `jj config set --user user.signing-key $KEY_ID`

### During Normal Operation

- Git automatically signs all commits with the configured key
- Jujutsu automatically signs all commits with the same key
- GPG agent caches the passphrase for 7 days (configurable)
- The key persists in the GPG keyring across rebuilds

## Troubleshooting

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

### Key ID Mismatch

If the wrong key is being used:

**Cause**: Multiple GPG keys in keyring

**Solution**:
1. List all secret keys: `gpg --list-secret-keys --keyid-format LONG`
2. Remove unwanted keys: `gpg --delete-secret-key KEY_ID`
3. Rebuild to re-import the correct key

## Security Considerations

- The GPG private key is encrypted with agenix and only decrypted at runtime
- The decrypted key exists only at `/run/agenix/gpg-private-key` (tmpfs, not persisted to disk)
- The key is imported into the GPG keyring but the keyring is protected by standard GPG permissions
- Always use `gpg --export-secret-key --armor` to export keys (never share the binary format)
- The agenix secret is accessible to all machines defined in `secrets/secrets.nix`

## Related Files

- `secrets/secrets.nix` - Defines which machines can access the GPG key
- `secrets/recreate-secrets.sh` - Interactive script to create/update secrets
- `flakes/hm-modules/modules/gpg.nix` - Main GPG module with activation scripts
- `flakes/hm-modules/modules/git/default.nix` - Git configuration (signing key set dynamically)
- `flakes/hm-modules/modules/jujutsu/default.nix` - Jujutsu configuration (inherits git signing key)
- `flakes/nixos-modules/modules/users/chris.nix` - GPG agent configuration

## Future Improvements

- [ ] Add support for multiple GPG keys
- [ ] Create a wrapper script to rotate GPG keys
- [ ] Add verification step to ensure key matches expected fingerprint
- [ ] Support for hardware security keys (YubiKey, etc.)