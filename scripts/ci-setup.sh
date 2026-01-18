#!/usr/bin/env bash
# CI setup script for SourceHut builds
# Configures Nix experimental features and cachix

set -euo pipefail

# Configure Nix
mkdir -p ~/.config/nix/
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
echo "max-jobs = auto" >> ~/.config/nix/nix.conf

# Setup cachix
cachix authtoken --stdin < ~/.ci_secrets/cachix_token
cachix use averagechris-dotfiles
