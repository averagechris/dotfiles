# GitHub input migration

## Destination

Track the approved migration of the remaining SourceHut-backed flake inputs to
GitHub sources, without changing package or module interfaces or the existing
nixpkgs pin.

## Notes

The user approved GitHub as the only source authority for this effort. Do not
contact SourceHut or use its network. The user also approved local
implementation of the plan. This map remains a discovery artifact and does not
authorize publication, host activation, deployment, or tracker issue creation.

The 13 direct project mirrors and the canonical site revision have been checked
against GitHub. The chosen graph has one shared `fleet` site input and one
shared `srht` input, with child `fleet` inputs following the root. The approved
GitHub-only source declarations and all 14 canonical locks are now migrated.
The locks contain no SourceHut URLs or SourceHut input node types. Keep the
existing interfaces, and treat the nixpkgs revision and its `nixos-unstable` ref
as fixed.

Decision frontier: [issues/](issues/)

Agents scan this directory for open, unblocked child decisions.

## Decisions so far

- [GitHub-only source policy](issues/01-github-only-policy.md): Use GitHub-only retrieval with no SourceHut network access, while preserving interfaces and the nixpkgs pin.
- [Direct mirror and SHA map](issues/02-direct-mirror-sha-map.md): All 13 direct projects have verified GitHub repositories and selected revisions, including gander at `3c3d674` and nitter-link at the existing `v0.1.4` commit.
- [Transitive fleet/site source](issues/03-transitive-fleet-site.md): Use the canonical GitHub site at `19416e3`, shared `srht` at `125f982`, mutual root follows, and child follows, without a separate fleet revision.
- [Fourteen-lock rollout and checks](issues/04-fourteen-lock-rollout.md): Execute one leaves-first 14-lock update with approved candidate files, root-level historical-SHA overrides only where the flake owns the declaration, a fixed nixpkgs object, graph checks, and drift validation. The source and lock migration is complete; behavior validation and PR CI remain pending.

## Not yet specified

- [Host behavior parity](issues/05-host-behavior-parity.md): Determine whether
  shared `fleet@19416e`/`srht@125f` changes active host packages, release
  apps/devShells, or package/module interfaces versus the baseline, and what
  evidence or tests distinguish expected release-only drift from unexpected host
  runtime drift before publication or deployment. PR CI remains pending.

## Out of scope

- Full removal of the `srht` CLI, its module, or its documentation is separate
  work and is not part of this input migration.
- A separate `averagechris/fleet` source or later fleet revision is not part of
  the chosen topology. The shared `fleet` input is the canonical site repository.
- Host deployment, activation, and post-change rollout are excluded. No host should be changed merely to complete discovery.
- Changes to package/module interfaces, the nixpkgs pin, or unrelated dependency updates are excluded.
- No SourceHut network access, external tracker issue creation, publication,
  host activation, or deployment is part of this map.
