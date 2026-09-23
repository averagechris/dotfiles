# Transitive fleet/site source

Type: research
Status: open
Blocked by: [Direct mirror and SHA map](02-direct-mirror-sha-map.md)

## Question

Should the flake inputs currently resolved from `averagechris.srht.site` be
mapped to `averagechris/fleet`, and if so, must that pinned GitHub source first
stop fetching SourceHut through its own `srht` input and release backend?

## Answer

## Evidence

- The root and host locks contain many `fleet` nodes whose locked source is the
  site repository, rather than one of the 13 direct project mirrors.
- GitHub has an `averagechris/fleet` repository. Its current `main` revision was
  `b10d6f06310828a22f9c12f0a431e5cde412039e` when checked on 2026-09-23.
- The GitHub fleet flake still declares an `srht` input and uses it for the
  default release backend, its `srht` app, and the `srht` package. A pinned
  GitHub fleet source therefore still fetches SourceHut today.
- The GitHub repository is a plausible candidate for the site repository, but no
  human answer has been recorded that it may replace the site input. Likewise,
  no answer has been recorded to remove the `srht` CLI or change fleet's release
  backend.
