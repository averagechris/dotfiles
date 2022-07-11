This is the configuration for pretty much every machine I work with. All of the
configurations are packaged into a single nix flake. To use on a brand new system
first, install nix (or use the installation iso), then link this repo's `flake.nix`
to `/etc/nixos/flake.nix`. Then run
`nixos-rebuild switch --use-remote-sudo --flake .#SYSTEM_NAME`

For subsequent builds, the argument `--flake .#SYSTEM_NAME` can be omitted since
the configuration will set they system's host name for you.
