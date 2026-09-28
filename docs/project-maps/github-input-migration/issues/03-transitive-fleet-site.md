# Transitive fleet/site source

Type: research
Status: resolved
Blocked by: [Direct mirror and SHA map](02-direct-mirror-sha-map.md)

## Question

What GitHub source and follows topology should replace the flake inputs currently
resolved from `averagechris.srht.site`, while keeping the existing interfaces and
avoiding SourceHut retrieval?

## Answer

Use the canonical GitHub site repository
[`averagechris/averagechris.github.io`](https://github.com/averagechris/averagechris.github.io)
as the shared `fleet` input, pinned to commit
`19416e3fc0c0415e39104476565ec0c375bce69b`. Use
[`averagechris/srht`](https://github.com/averagechris/srht) as the shared
`srht` input, pinned to `125f982de6fe846c55896cec9b5de746596b872b`.

The root `fleet` and `srht` inputs retain their mutual follows. Every child
flake's `fleet` input follows the shared root `fleet`, so lock regeneration does
not create one site node per child. The 13 direct project inputs use floating
GitHub owner/name URLs in the flake declarations. The lock update overrides
those inputs to the chosen historical revisions instead of putting revisions in
the source URLs. That keeps the normal `update-flakes` behavior available.

This answer chooses the site repository directly. It does not add a separate
`averagechris/fleet` source. A disposable prototype used gander at `3c3d674`,
the site at `19416e3`, `srht` at `de37fe`, and a separate fleet revision at
`56cce9`. With the follows broken, that prototype still locked and evaluated
offline with zero SourceHut URLs. The later separate fleet revision was judged
unnecessary drift, so it is not part of this plan.

Removing the `srht` CLI or changing the fleet release backend is a separate
decision. This input migration keeps the existing package and module interfaces.

## Evidence

- The root and host locks contain `fleet` nodes whose locked source is the site
  repository, rather than one of the 13 direct project mirrors.
- GitHub API verification found the canonical site commit
  `19416e3fc0c0415e39104476565ec0c375bce69b` and the root `srht` commit
  `125f982de6fe846c55896cec9b5de746596b872b`.
- The disposable prototype locked and evaluated offline without SourceHut URLs.
  It tested the follows break and the historical gander/site pins, but the
  separate fleet pin was not needed for the chosen topology.
