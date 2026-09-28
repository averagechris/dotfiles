# Host behavior parity

Type: research
Status: open
Blocked by: [Fourteen-lock rollout and checks](04-fourteen-lock-rollout.md)

## Question

Does shared `fleet@19416e`/`srht@125f` change active host packages, release
apps/devShells, or package/module interfaces versus the baseline, and what
evidence or tests would distinguish expected release-only drift from unexpected
host runtime drift before publication or deployment?

## Answer

The corrected read-only lock comparison shows that the direct `srht` input kept
the same source contents in the root, `suremac`, and `tater` locks. In each old
lock, the direct input selected the SourceHut node at revision
`125f982de6fe846c55896cec9b5de746596b872b` with narHash
`sha256-EHah1RPqtHskPoLJkJFcyQJy1T3jUNqVS0zIHI0CxYc=`. The new GitHub node has
the same revision and narHash. The old `de37fece3ea5226cbf8fda5f4775847d626bce7b`
node was a nested variant, not the active direct runtime input or an active host
runtime blocker.

This does not establish full host behavior parity. The old host `drvPath` values
remain unverified because the sanitized old baseline omitted the encrypted age
file needed for that comparison. Keep this issue open until those values, or an
equivalent baseline, can be checked. Do not treat the matching `srht` source
identity as proof that host packages, release apps, devShells, or interfaces are
unchanged.
