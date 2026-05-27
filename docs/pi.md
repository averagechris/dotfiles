# Pi

This repository packages the [Pi coding agent](https://pi.dev/) and exposes a
minimal Home Manager module for installing it.

## Package

The `pkgs.pi` and `pkgs.pi-coding-agent` attributes come from the shared
`base-lib` overlay. They install Pi's upstream native release archive for the
current platform rather than building from npm source.

The package is pinned to a specific upstream version and hash in
`flakes/base-lib/packages/pi-coding-agent.nix`.

Pi is intentionally **not** a flake input right now. The goal is to make Pi
updates explicit and reviewable instead of letting routine flake updates advance
a fast-moving coding agent automatically. This is especially important because
Pi is distributed through the npm ecosystem upstream, even though this package
uses the native release archive rather than resolving npm dependencies during a
Nix build.

Tradeoffs of the current approach:

- Updates require editing `flakes/base-lib/packages/pi-coding-agent.nix` by hand.
- Routine `scripts/update-flakes.sh` runs cannot accidentally pull a fresh Pi
  release.
- The review diff for an update is small and obvious: version plus platform
  hashes.
- Building does not run npm, Bun, or dependency lifecycle scripts.
- Local patches or a long-lived fork would be awkward; if we start patching Pi,
  reconsider using a flake input or forked source checkout.

Prefer keeping Pi manually pinned until there is a concrete need to consume Pi
source directly, apply patches, or track a fork. If Pi becomes a flake input in
the future, include it in the update cooldown list and pin it to an explicit tag
or revision rather than an unreviewed moving branch.

## Updating Pi

Do not update Pi as part of routine flake maintenance. Before bumping Pi:

1. Wait at least the same cooldown window used for fast-moving agent inputs
   (currently 7 days by default in `scripts/update-flakes.sh`).
2. Review the upstream release notes and recent issues for the target release.
3. Prefer a released version over an arbitrary branch commit.
4. Update `version` and the platform hashes in
   `flakes/base-lib/packages/pi-coding-agent.nix`.
5. Build the package and verify `pi --version`.
6. Run the relevant Home Manager/module checks before committing.

Useful validation commands:

```bash
nix build --impure --expr 'let flake = builtins.getFlake "path:/Users/chris/dotfiles/flakes/base-lib"; system = builtins.currentSystem; pkgs = import flake.inputs.nixpkgs { inherit system; overlays = [ flake.overlays.default ]; config.allowUnfree = true; }; in pkgs.pi' --no-link
nix flake check ./flakes/hm-modules
```

## Home Manager

Enable Pi with:

```nix
programs.pi.enable = true;
```

The module only installs the package for now. Configuration options for Pi
settings, packages, skills, prompts, or environment variables can be added later
after deciding how much of Pi's `~/.pi/agent/settings.json` should be managed by
Home Manager.

To override the installed package:

```nix
programs.pi = {
  enable = true;
  package = pkgs.pi;
};
```

## Runtime state

Pi stores global settings, credentials, sessions, and installed Pi packages
under `~/.pi/agent/`. This module intentionally does not manage that directory
yet.
