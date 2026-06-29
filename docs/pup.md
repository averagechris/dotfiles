# Pup Datadog CLI

`pkgs.pup` packages Datadog's Pup CLI from the official GitHub release
archives. The derivation lives at `flakes/base-lib/packages/pup.nix` and is
exposed through the shared base-lib overlay.

## suremac integration

`suremac` installs `pup` in Chris's Home Manager `home.packages` and exposes it
to OpenCode agents as a host-specific tool named `pup` with the prompt
description `Datadog CLI`.

Pup supports OAuth login and Datadog API/app-key environment variables. The
Nix package does not manage credentials; use Pup's own authentication flow or
provide the Datadog environment variables required by the command you run.

```bash
pup auth login
pup auth status
pup monitors list
```

## Updates

`pup` is enrolled in `manual-package-updates.json` as an archive package with an
explicit version requirement. Update it through the manual-package flow so the
version and all platform hashes are changed together:

```bash
update-flakes --manual-packages-only \
  --manual-package pup \
  --manual-version pup=<version>
```

The manifest keeps the normal cooldown enabled. Override it only after reviewing
fresh upstream releases intentionally.
