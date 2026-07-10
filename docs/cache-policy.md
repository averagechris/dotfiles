# Cache Policy and Observability

This repository treats evaluation, substitution, local builds, remote builds, and
cache publication as separate policy decisions.

## Environment matrix

| Environment | Substituters/keys | Builders | Publication policy |
| --- | --- | --- | --- |
| NixOS hosts via `nixosModules.common` | Official `cache.nixos.org`, `averagechris-dotfiles`, `nix-community`, `nixpkgs-wayland`, `devenv`, and `helix`; effective settings include the NixOS module's built-in official key plus each configured Cachix key | Host-local unless a host adds builders | Pull from configured caches. Host closures stay local unless measured evidence justifies publishing them. |
| `suremac` with Determinate Nix | Imperative Determinate Nix daemon config, not nix-darwin-owned `nix.settings`; verify at runtime with `nix config show substituters trusted-public-keys builders builders-use-substitutes` | Determinate/runtime config only | Pull from configured caches. Darwin differs from NixOS because daemon settings are not declaratively enforced here. |
| Hosted SourceHut auto CI | `scripts/ci-setup.sh` enables flakes, authenticates Cachix, runs `cachix use averagechris-dotfiles`, then reports effective revision/system/Nix version/cache/builder settings | Hosted runner local builder; no assumed remote builders | Eval-only jobs do not publish. Current SourceHut jobs are pull-only unless a job explicitly invokes a push command. |
| Manual SourceHut manifests | Same setup as auto CI | Same runner class unless the manifest selects a different arch | Pull-only unless an explicit push is added for that manifest. Full-fleet/host closure work remains manual and may exceed hosted VM capacity. |
| Cross-repo selected outputs | Project-specific Cachix use | Project-specific | Keep publishing selected outputs when they are known useful across repos. |

## Publication policy

- Evaluation-only jobs never publish cache entries.
- SourceHut setup must keep `cachix use averagechris-dotfiles` and token
  authentication operational, but using a cache is not the same as pushing to it.
- Host system closures remain local by default. Publish them only after concrete
  measurements show enough repeated substitution benefit to justify storage,
  upload time, and cache churn.
- Cross-repo selected outputs remain eligible for publication when they are known
  to save work outside this repository.
- Dotfiles check outputs should be added to publication only after measured
  benefit; do not publish broad check/fleet closures speculatively.

## Current CI shape

GitHub Actions is retired for this repository. SourceHut is the only routine CI
surface. git.sr.ht auto-submits only `.builds/lint-check.yml`,
`.builds/active-host-evals.yml`, and `.builds/coverage-checks.yml`; `.srht/`
manifests are manual diagnostics or heavyweight validation.

## Observability

Routine SourceHut setup reports revision, `builtins.currentSystem`, Nix version,
substituters, trusted public keys, builders, `builders-use-substitutes`,
`max-jobs`, and `cores`. Missing settings are reported as unavailable instead of
failing the job. Trap diagnostics reports the same cache/builder fields before
the disk and dry-run measurements.

`flake-benchmark` metadata records substituters, trusted public keys, builders,
and `builders-use-substitutes` in addition to revision, dirty state, system, Nix
version, raw vendor version output, lock hash, and benchmark config. These are
additive fields in the existing JSON Lines metadata record.
