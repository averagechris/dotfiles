# Troubleshooting Guides

Common issues and their solutions for this NixOS/Darwin dotfiles repository.

## Guides

- [Sudo setuid permission error (`nobody:nogroup` ownership)](./sudo-setuid-nobody-nogroup.md) - When sudo and other setuid binaries fail due to incorrect file ownership
- [GPG agent lock / keyboxd timeout](./gpg-agent-lock.md) - When GPG signing fails with "waiting for lock" errors after reboot
- [Home Manager App Management permission fails on macOS](./home-manager-app-management.md) - When darwin-rebuild fails to update apps due to App Management permissions
- [Home Manager activation timeout](./home-manager-activation-timeout.md) - When `nixos-rebuild switch` hangs while starting GUI user services
- [Home Manager package path collisions](./home-manager-package-collisions.md) - When two packages in `home.packages` provide the same path
- [Hyprland invalid source path during flake evaluation](./hyprland-invalid-source-path.md) - When `nix flake check --no-build` fails on Hyprland hosts
- [Hyprland build fails fetching glaze with FetchContent](./hyprland-glaze-fetchcontent.md) - When the pinned Hyprland build cannot find glaze 7.x in nixpkgs
- [MT7925e Wi-Fi instability on tater](./mt7925e-network-instability.md) - When tater's Wi-Fi disconnects or stops passing traffic
