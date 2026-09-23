# GitHub input migration

## Destination

Produce a delivery-ready plan for replacing the remaining SourceHut-backed flake
inputs with pinned GitHub sources, without changing package or module interfaces
or the existing nixpkgs pin.

## Notes

The user approved GitHub as the only source authority for this effort. Do not
contact SourceHut or use its network. This is discovery only. It does not
authorize code or lock edits, host activation, deployment, publication, or
tracker issue creation.

The 13 direct project mirrors have been checked against GitHub. The remaining
uncertainty is in transitive fleet/site inputs and in updating every canonical
lock consistently. Keep the existing interfaces, and treat the nixpkgs revision
and its `nixos-unstable` ref as fixed.

Decision frontier: [issues/](issues/)

Agents scan this directory for open, unblocked child decisions.

## Decisions so far

- [GitHub-only source policy](issues/01-github-only-policy.md): Use GitHub-only retrieval with no SourceHut network access, while preserving interfaces and the nixpkgs pin.
- [Direct mirror and SHA map](issues/02-direct-mirror-sha-map.md): The 13 direct projects have verified GitHub repositories and pinned-SHA candidates, with one gander revision exception recorded.

## Not yet specified

- [Transitive fleet/site source](issues/03-transitive-fleet-site.md): Decide how the `fleet`/site input is mapped and whether a pinned GitHub fleet source may retain a SourceHut fetch.
- [Fourteen-lock rollout and checks](issues/04-fourteen-lock-rollout.md): Decide the safe update order and completion gates for all 14 canonical locks.

## Out of scope

- Full removal of the `srht` CLI, its module, or its documentation is not part of this effort unless a narrowly targeted change is required to eliminate a SourceHut node from the lock graph. No human decision to remove it is assumed.
- Replacing the site repository is not assumed. That remains an open decision in [Transitive fleet/site source](issues/03-transitive-fleet-site.md).
- Host deployment, activation, and post-change rollout are excluded. No host should be changed merely to complete discovery.
- Changes to package/module interfaces, the nixpkgs pin, or unrelated dependency updates are excluded.
- No SourceHut network access, external tracker issue creation, or publication is allowed.
