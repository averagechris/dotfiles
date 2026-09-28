# Fourteen-lock rollout and checks

Type: research
Status: resolved
Blocked by: [Transitive fleet/site source](03-transitive-fleet-site.md), [Direct mirror and SHA map](02-direct-mirror-sha-map.md)

## Question

What update order and completion gates should replace the resolved SourceHut
inputs across all 14 canonical locks while retaining the exact root nixpkgs
revision and `nixos-unstable` ref?

## Answer

Treat the migration as one conceptual change, then regenerate locks in a fixed
leaves-first order. The approved source declarations and all 14 canonical locks
have now been migrated. This document records the procedure and the remaining
validation gates. It does not claim behavioral parity or deployment safety.

1. Complete the approved source declarations and follows before generating
   candidates. Use floating GitHub `github:averagechris/<project>` URLs for the
   direct projects. Keep the shared `fleet` URL pointed at
   `averagechris/averagechris.github.io`, and keep shared `srht` on
   `averagechris/srht`. Make each child `fleet` input follow the root shared
   input, and retain the mutual root `fleet`/`srht` follows. Do not put `rev` in
   the declared URLs. In particular, retain `nitter-link` at the `v0.1.4`
   commit `e627d315a2433dd4170d901a0ea9dbd9dd518784`.
2. Generate lock candidates in this order, from leaves toward the root:

   1. `flakes/base-lib`
   2. `flakes/hm-modules`
   3. `flakes/darwin-modules`
   4. `flakes/nixos-modules`
   5. Generic hosts: `cruber`, `taz`, `tom`, `tootsie`, `trainwreck`, and
      `trap`
   6. The separately reviewed hosts: `suremac`, `tater`, and `thorny`
   7. The repository root

   The `hm-modules` candidate may need a `parent: []` path entry. Accept that
   generated shape when it is required by the leaves-first graph; do not use a
   nested override to recreate the old parent graph.
3. For each flake, update only its named direct path inputs, offline, into an
   approved temporary lock file:

   ```text
   nix flake update <direct path-input names> \
     --offline \
     --flake 'path:<absolute repo root>?dir=<subflake>' \
     --output-lock-file <approved temp>
   ```

   For the root flake, omit `?dir=<subflake>`. Validate the temporary JSON
   before copying it to that flake's `flake.lock`. Never use a bare `nix flake
   lock`, `--recreate-lock-file`, or a nested override such as
   `base-lib/titlecase`. Plain locking can lazily retain path parents, while a
   nested `--override-input base-lib/titlecase` can preserve the old SourceHut
   `original` and lose the intended follows and nixpkgs pin.
4. The flakes with their own direct GitHub source declaration edits are the
   root, `suremac`, `tater`, and `thorny`. For those invocations only, add a
   root-level override for each owned input, using the exact historical SHA from
   [Direct mirror and SHA map](02-direct-mirror-sha-map.md):

   ```text
   --override-input <name> github:averagechris/<name>/<exact historical sha>
   ```

   Do not turn that into a nested path such as `base-lib/<name>`. Do not use a
   SourceHut URL or fetch SourceHut to resolve a miss. A GitHub-only prefetch of
   an exact approved source is allowed when the offline cache does not contain
   it.
5. Keep every lock's nixpkgs object at
   `e554fab72f81915600f3f449b786fd9af40439a5` and retain
   `original.ref = "nixos-unstable"`. Apply that same locked nixpkgs object to
   every standalone lock. Do not let lock regeneration update unrelated inputs.
6. Validate each candidate JSON before copying it. Check every selected direct
   input's exact `rev` and `narHash`, the exact locked nixpkgs revision and
   `nixos-unstable` original ref, and the absence of SourceHut URLs or SourceHut
   input types. Inspect the graph for one shared `fleet` and one shared `srht`
   node, child follows to the shared `fleet`, and no duplicate path-flake graph.
   The completed migration checked all 14 locks for zero SourceHut strings,
   including `sourcehut`, `sr.ht`, `git.sr.ht`, and `srht.site`. The `srht` input
   name and the `srht` package/module remain expected because removing the CLI is
   separate work.
7. Treat the shared `fleet` at `19416e3fc0c0415e39104476565ec0c375bce69b`
   and shared `srht` at
   `125f982de6fe846c55896cec9b5de746596b872b` as a possible behavior change.
   Their mutual follows collapse earlier variant revisions. That may affect
   release apps or development shells, and the migration has not proved that
   drift inert. Compare those outputs as well as host evaluations.
8. For behavior validation, compare the affected host
   `config.system.build.toplevel.drvPath` values with any recorded pre-migration
   values using `nix eval ... --raw --no-write-lock-file`, with
   `--option allow-import-from-derivation false --option eval-cache false`.
   A changed path needs investigation, even when the difference is a legitimate
   consequence of the shared follows. Do not deploy until the difference is
   understood. Then run
   `jj lint`, the fast lock and graph checks, the full root `nix flake check`,
   and the applicable standalone host checks. Keep the package/module interface
   and nixpkgs pin unchanged.

The implementation should stop if a lock introduces a second fleet/site node,
loses a child follow, changes the nixpkgs revision or ref, leaves a SourceHut
URL or input type, or produces an unexplained host derivation-path or release
app/devShell change. The final change must still be reviewed as a plan
execution, not treated as proof that a host is safe to activate or deploy.

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
duplicate path-flake graphs. The migration evidence is:

- all 14 canonical locks contain zero SourceHut URLs and zero SourceHut input
  node types;
- the root lock has 91 nodes and the `hm-modules` lock has 32 nodes;
- the active host locks have 51 nodes for `suremac`, 66 for `tater`, and 64 for
  `thorny`;
- the root offline `nix flake check --no-build` passed; and
- active host evaluations produced `drvPath` values.

These host evaluations do not establish exact derivation-path parity. Full
behavior validation, including release-app/devShell drift checks and applicable
standalone checks, remains pending. PR CI also remains pending. No publication,
host activation, or deployment has occurred. The gander revision is not an
exception: the selected
`3c3d674fa4eeab7c47085e9e7617231183d415a8` commit exists in its GitHub mirror.

The Wise follow-up also supplied disposable offline proof references for the
corrected procedure. The Darwin lock check recorded four `owner`/`type` lines.
The `tom` check went from `149` to `36` and reported zero SourceHut. Those were
candidate-proof references; the canonical migration is now complete, but the
behavior and CI gates above still need to pass before publication or deployment.
