# Cache policy and observability

This repository treats evaluation, substitution, local builds, remote builds, and
cache publication as separate policy decisions.

## Environment matrix

| Environment | Substituters/keys | Builders | Publication policy |
| --- | --- | --- | --- |
| NixOS hosts via `nixosModules.common` | Official `cache.nixos.org`, `averagechris-dotfiles`, `nix-community`, `nixpkgs-wayland`, `devenv`, and `helix`; effective settings include the NixOS module's built-in official key plus each configured Cachix key | Host-local unless a host adds builders | Pull from configured caches. Host closures stay local unless measured evidence justifies publishing them. |
| `suremac` with Determinate Nix | Imperative Determinate Nix daemon config, not nix-darwin-owned `nix.settings`; verify at runtime with `nix config show substituters trusted-public-keys builders builders-use-substitutes` | Determinate/runtime config only | Pull from configured caches. Darwin differs from NixOS because daemon settings are not declaratively enforced here. |
| GitHub Actions CI | `cachix/install-nix-action` installs Nix; each routine CI job configures the public `averagechris-dotfiles` cache with `cachix/cachix-action`, without an auth token | GitHub-hosted `ubuntu-24.04` local builder; no assumed remote builders | Read-only, secretless checks. Jobs may substitute from the public cache and never push. |
| Manual heavyweight checks | The invoking host's configured substituters and keys | Host-local or explicitly configured builders | Full-fleet and host closure work stays local unless deliberately run elsewhere; no implicit publication. |
| Cross-repo selected outputs | Project-specific Cachix use | Project-specific | Keep publishing selected outputs when they are known useful across repos. |

## Publication policy

- Evaluation-only jobs never publish cache entries.
- GitHub Actions uses configured public caches without authentication; using a
  cache is not the same as pushing to it.
- Host system closures remain local by default. Publish them only after concrete
  measurements show enough repeated substitution benefit to justify storage,
  upload time, and cache churn.
- Cross-repo selected outputs remain eligible for publication when they are known
  to save work outside this repository.
- Dotfiles check outputs should be added to publication only after measured
  benefit; do not publish broad check/fleet closures speculatively.

## Current CI shape

GitHub Actions is the repository's routine CI surface. The
`dotfiles-checks.yml` workflow runs fast checks in the minimal `.#ci` shell,
active host evaluations, and selected coverage checks. Full-fleet and native
trainwreck tiers remain manual and local; trap diagnostics are separate manual
commands used only for targeted investigation.

## Observability

When diagnosing cache or builder behavior locally, record revision,
`builtins.currentSystem`, Nix version, substituters, trusted public keys,
builders, `builders-use-substitutes`, `max-jobs`, and `cores` alongside disk and
dry-run measurements.

`flake-benchmark` metadata records substituters, trusted public keys, builders,
and `builders-use-substitutes` in addition to revision, dirty state, system, Nix
version, raw vendor version output, lock hash, and benchmark config. These are
additive fields in the existing JSON Lines metadata record.
