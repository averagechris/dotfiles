# Fourteen-lock rollout and checks

Type: research
Status: open
Blocked by: [Transitive fleet/site source](03-transitive-fleet-site.md), [Direct mirror and SHA map](02-direct-mirror-sha-map.md)

## Question

What update order and completion gates should replace the resolved SourceHut
inputs across all 14 canonical locks while retaining the exact root nixpkgs
revision and `nixos-unstable` ref?

## Answer

## Evidence

The canonical lock set is:

- `flake.lock`
- `flakes/base-lib/flake.lock`
- `flakes/darwin-modules/flake.lock`
- `flakes/hm-modules/flake.lock`
- `flakes/nixos-modules/flake.lock`
- `flakes/hosts/cruber/flake.lock`
- `flakes/hosts/suremac/flake.lock`
- `flakes/hosts/tater/flake.lock`
- `flakes/hosts/taz/flake.lock`
- `flakes/hosts/thorny/flake.lock`
- `flakes/hosts/tom/flake.lock`
- `flakes/hosts/tootsie/flake.lock`
- `flakes/hosts/trainwreck/flake.lock`
- `flakes/hosts/trap/flake.lock`

The existing flake-hygiene guidance requires all 14 locks to share the root
nixpkgs revision and retain the `nixos-unstable` ref. It also warns against
duplicate path-flake graphs. The GitHub workflow currently runs fast checks,
active host evaluations, and coverage checks, while the full root flake check is
available as a separate tier. The rollout decision must turn those facts into a
single reproducible sequence, including how to prove that no SourceHut fetch
remains and how to handle the gander revision exception.
