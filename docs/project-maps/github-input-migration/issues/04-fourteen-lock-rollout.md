# Fourteen-lock rollout and checks

Type: research
Status: resolved (PLAN)
Blocked by: [Transitive fleet/site source](03-transitive-fleet-site.md), [Direct mirror and SHA map](02-direct-mirror-sha-map.md)

## Question

What update order and completion gates should replace the resolved SourceHut
inputs across all 14 canonical locks while retaining the exact root nixpkgs
revision and `nixos-unstable` ref?

## Answer

Treat the migration as one conceptual change, then regenerate the 14 locks in
the same order every time. This is the approved implementation plan. It does not
claim that the source declarations or lock files have been changed here.

1. Update the source declarations and follows first. Use floating GitHub
   `github:averagechris/<project>` URLs for the 13 direct projects. Keep the
   shared `fleet` URL pointed at
   `averagechris/averagechris.github.io`, and keep shared `srht` on
   `averagechris/srht`. Make each child `fleet` input follow the root shared
   input, and retain the mutual root `fleet`/`srht` follows.
2. Regenerate the locks in this order: the root lock, `base-lib`,
   `darwin-modules`, `hm-modules`, `nixos-modules`, then the host locks in the
   order listed below. For each lock, use `nix flake lock --override-input` to
   resolve the direct inputs and shared inputs at their selected historical
   revisions. Do not put `rev` in the declared URLs. In particular, retain
   `nitter-link` at the `v0.1.4` commit `e627d315a2433dd4170d901a0ea9dbd9dd518784`.
3. Keep the root nixpkgs lock at
   `e554fab72f81915600f3f449b786fd9af40439a5` and retain
   `original.ref = "nixos-unstable"`. Apply that same locked nixpkgs object to
   every standalone lock. Do not let lock regeneration update unrelated inputs.
4. After each lock, inspect the graph for one shared `fleet` and one shared
   `srht` node, child follows to the shared `fleet`, and no duplicate path-flake
   graph. At the end, check all locks for zero SourceHut strings, including
   `sourcehut`, `sr.ht`, `git.sr.ht`, and `srht.site`. The `srht` input name and
   the `srht` package/module remain expected because removing the CLI is separate
   work.
5. Capture the affected host `config.system.build.toplevel.drvPath` values
   before the implementation with `nix eval ... --raw --no-write-lock-file`,
   using `--option allow-import-from-derivation false --option eval-cache false`,
   and compare them with the values after the lock update. A changed path needs
   an explanation. Then run `jj lint`, the fast lock and graph checks, the full
   root `nix flake check`, and the applicable standalone host checks. Keep the
   package/module interface and nixpkgs pin unchanged.

The implementation should stop if a lock introduces a second fleet/site node,
loses a child follow, changes the nixpkgs revision or ref, leaves a SourceHut
URL, or produces an unexplained host derivation-path change. The final change
must still be reviewed as a plan execution, not treated as proof that a host is
safe to activate or deploy.

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
remains. The gander revision is not an exception: the selected
`3c3d674fa4eeab7c47085e9e7617231183d415a8` commit exists in its GitHub mirror.
