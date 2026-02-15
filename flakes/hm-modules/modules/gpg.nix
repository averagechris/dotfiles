# GPG Module with Automatic Key Import from Agenix
#
# This module provides automatic GPG key management for git and jj (jujutsu)
# commits. It imports a GPG private key from an agenix secret during home-manager
# activation and configures both git and jj to use it for signing.
#
# Features:
# - Imports GPG private key from /run/agenix/gpg-private-key
# - Reads GPG key ID from /run/agenix/gpg-key-id
# - Configures git and jj with the signing key from agenix
# - Sets GPG_TTY environment variable for proper pinentry functionality
#
# Usage:
# 1. Store your GPG private key in secrets/gpg-private-key.age (use recreate-secrets.sh)
# 2. Store your GPG key ID in secrets/gpg-key-id.age (just the key ID, e.g., "623745A83D6C9C02")
# 3. Configure the secrets in your host's configuration.nix:
#    age.secrets.gpg-private-key = { ... };
#    age.secrets.gpg-key-id = { ... };
# 4. Enable the module: dotfiles.gpg.enable = true;
#
# The private key is imported during home-manager activation, so it persists across
# rebuilds but is not stored in the Nix store. The GPG agent is configured
# separately in the NixOS configuration (see flakes/nixos-modules/modules/users/chris.nix).
{
  config,
  lib,
  pkgs,
  dotfiles_lib,
  secrets ? {},
  ...
}: let
  cfg = config.dotfiles.gpg;
  hasSecrets = secrets ? gpg-private-key && secrets ? gpg-key-id;
in
  with lib; {
    options.dotfiles.gpg = with dotfiles_lib.options; {
      enable = mkDefaultEnabledOption "GPG configuration with automatic key import from agenix.";
    };

    config = mkIf cfg.enable (
      mkMerge [
        {
          # Set GPG_TTY for proper pinentry functionality
          # This ensures GPG pinentry prompts appear in the correct terminal
          home.sessionVariables.GPG_TTY = "$(tty)";

          # Ensure GPG agent is started and accessible
          # This enables passphrase caching so you don't have to enter it for every commit
          programs.gpg = {
            enable = true;
            # GPG agent settings are configured in the NixOS module
            # (see flakes/nixos-modules/modules/users/chris.nix)
            # default-cache-ttl = 604800 (7 days)
            # max-cache-ttl = 31536000 (1 year)
          };

          # Clean stale GPG locks on startup to prevent hangs
          # This fixes issues where keyboxd holds a stale lock after reboot
          systemd.user.services.gpg-agent-cleanup = {
            Unit = {
              Description = "Clean stale GPG locks and restart agent";
              After = ["graphical-session.target"];
            };
            Service = {
              Type = "oneshot";
              ExecStart = "${pkgs.gnupg}/bin/pkill -9 keyboxd 2>/dev/null || true; ${pkgs.gnupg}/bin/gpgconf --kill gpg-agent 2>/dev/null || true; ${pkgs.gnupg}/bin/gpgconf --launch gpg-agent 2>/dev/null || true";
            };
            Install = {WantedBy = ["graphical-session.target"];};
          };

          # Configure git to sign commits by default
          # The signing key will be read from agenix during activation
          programs.git = {
            enable = true;
            signing = {
              signByDefault = true;
              key = ""; # Placeholder, will be set by activation script
            };
          };

          # Configure jj to use GPG signing
          programs.jujutsu.settings.signing = {
            backend = "gpg";
            behavior = "own";
          };
        }

        # If we have GPG secrets, configure them during activation
        (mkIf hasSecrets {
          # Import GPG key during home-manager activation
          # This runs after the writeBoundary to ensure /run/agenix is mounted
          home.activation.import-gpg-key = lib.hm.dag.entryAfter ["writeBoundary"] ''
            if [[ -f ${secrets.gpg-private-key.path} ]]; then
              echo "Importing GPG private key..."
              ${pkgs.gnupg}/bin/gpg --batch --import ${secrets.gpg-private-key.path} 2>/dev/null || true
            fi
          '';

          # Read the key ID from agenix and configure git/jj
          home.activation.configure-signing-key = lib.hm.dag.entryAfter ["import-gpg-key"] ''
            if [[ -f ${secrets.gpg-key-id.path} ]]; then
              echo "Configuring signing key..."
              KEY_ID=$(cat ${secrets.gpg-key-id.path} 2>/dev/null | tr -d '\n')
              if [[ -n "$KEY_ID" ]]; then
                # Configure git signing key
                ${pkgs.git}/bin/git config --global user.signingkey "$KEY_ID" 2>/dev/null || true

                # Configure jj signing key
                ${pkgs.jujutsu}/bin/jj config set --user user.signing-key "$KEY_ID" 2>/dev/null || true

                echo "Signing key configured: $KEY_ID"
              fi
            fi
          '';
        })
      ]
    );
  }
