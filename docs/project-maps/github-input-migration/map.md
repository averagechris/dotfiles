# GitHub input migration

## Destination

Produce a delivery-ready plan for replacing the remaining SourceHut-backed flake
inputs with pinned GitHub sources, without changing package or module interfaces
or the existing nixpkgs pin.

## Notes

The user approved GitHub as the only source authority for this effort. Do not
contact SourceHut or use its network. The user also approved local
implementation of the plan. This map remains a discovery artifact and does not
authorize publication, host activation, deployment, or tracker issue creation.

The 13 direct project mirrors and the canonical site revision have been checked
against GitHub. The chosen graph has one shared `fleet` site input and one
shared `srht` input, with child `fleet` inputs following the root. The remaining
work is to implement and validate the ordered 14-lock update. Keep the existing
interfaces, and treat the nixpkgs revision and its `nixos-unstable` ref as fixed.

Decision frontier: [issues/](issues/)

Agents scan this directory for open, unblocked child decisions.

## Decisions so far

- [GitHub-only source policy](issues/01-github-only-policy.md): Use GitHub-only retrieval with no SourceHut network access, while preserving interfaces and the nixpkgs pin.
- [Direct mirror and SHA map](issues/02-direct-mirror-sha-map.md): All 13 direct projects have verified GitHub repositories and selected revisions, including gander at `3c3d674` and nitter-link at the existing `v0.1.4` commit.
- [Transitive fleet/site source](issues/03-transitive-fleet-site.md): Use the canonical GitHub site at `19416e3`, shared `srht` at `125f982`, mutual root follows, and child follows, without a separate fleet revision.
- [Fourteen-lock rollout and checks](issues/04-fourteen-lock-rollout.md): Execute one ordered 14-lock update with override-pinned historical revisions, a fixed nixpkgs object, graph checks, and host drv-path comparison.

## Remaining fog

- Implement the approved source and follows changes, regenerate all 14 locks in
  order, and investigate any check or host drv-path difference that appears.

## Out of scope

- Full removal of the `srht` CLI, its module, or its documentation is separate
  work and is not part of this input migration.
- A separate `averagechris/fleet` source or later fleet revision is not part of
  the chosen topology. The shared `fleet` input is the canonical site repository.
- Host deployment, activation, and post-change rollout are excluded. No host should be changed merely to complete discovery.
- Changes to package/module interfaces, the nixpkgs pin, or unrelated dependency updates are excluded.
- No SourceHut network access, external tracker issue creation, publication,
  host activation, or deployment is part of this map.
