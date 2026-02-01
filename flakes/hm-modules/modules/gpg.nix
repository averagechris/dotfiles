# GPG Module with Automatic Key Import from Agenix
#
# This module provides automatic GPG key management for git and jj (jujutsu)
# commits. It imports a GPG private key from an agenix secret during home-manager
# activation and configures both git and jj to use it for signing.
#
# Features:
# - Imports GPG private key from /run/agenix/gpg-private-key
# - Automatically detects the key ID from the imported key
# - Configures git to sign commits with the detected key
# - Configures jj (jujutsu) to use the same signing key
# - Sets GPG_TTY environment variable for proper pinentry functionality
#
# Usage:
# 1. Store your GPG private key in secrets/gpg-private-key.age (use recreate-secrets.sh)
# 2. Configure the secret path in your host's configuration.nix:
#    _module.args = { gpgPrivateKeyPath = config.age.secrets.gpg-private-key.path; };
# 3. Enable the module: dotfiles.gpg.enable = true;
#
# The key is imported during home-manager activation, so it persists across
# rebuilds but is not stored in the Nix store. The GPG agent is configured
# separately in the NixOS configuration (see flakes/nixos-modules/modules/users/chris.nix).
{
  config,
  lib,
  pkgs,
  dotfiles_lib,
  gpgPrivateKeyPath,
  ...
}: let
  cfg = config.dotfiles.gpg;
in
  with lib; {
    options.dotfiles.gpg = with dotfiles_lib.options; {
      enable = mkDefaultEnabledOption "GPG configuration with automatic key import from agenix.";
    };

    config = mkIf cfg.enable (mkMerge [
      {
        # Set GPG_TTY for proper pinentry functionality
        # This ensures GPG pinentry prompts appear in the correct terminal
        home.sessionVariables.GPG_TTY = "$(tty)";

        # Configure git to sign commits by default
        # The signing key will be set dynamically during activation after importing the GPG key
        programs.git = {
          enable = true;
          signing = {
            signByDefault = true;
            key = null; # Will be set after key import by the activation script
          };
        };
      }

      # If a GPG private key path is provided, import it and configure signing
      # The gpgPrivateKeyPath argument should point to /run/agenix/gpg-private-key
      (mkIf (gpgPrivateKeyPath != null) {
        # Import GPG key during home-manager activation
        # This runs after the writeBoundary to ensure /run/agenix is mounted
        home.activation.import-gpg-key = lib.hm.dag.entryAfter ["writeBoundary"] ''
          if [[ -f ${gpgPrivateKeyPath} ]]; then
            echo "Importing GPG private key..."
            ${pkgs.gnupg}/bin/gpg --batch --import ${gpgPrivateKeyPath} 2>/dev/null || true
          fi
        '';

        # Configure git and jj signing keys after importing the GPG key
        # Extracts the key ID from the imported GPG key and configures both tools
        home.activation.configure-signing-keys = lib.hm.dag.entryAfter ["import-gpg-key"] ''
          if [[ -f ${gpgPrivateKeyPath} ]]; then
            echo "Configuring signing keys..."
            KEY_ID=$(${pkgs.gnupg}/bin/gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep "sec" | head -n1 | sed 's/.*\///' | cut -d' ' -f1)
            if [[ -n "$KEY_ID" ]]; then
              ${pkgs.git}/bin/git config --global user.signingkey "$KEY_ID"
              ${pkgs.jujutsu}/bin/jj config set --user user.signing-key "$KEY_ID" 2>/dev/null || true
              echo "Signing keys configured: $KEY_ID"
            fi
          fi
        '';
      })
    ]);
  }
