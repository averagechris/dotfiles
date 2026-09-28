# Direct mirror and SHA map

Type: research
Status: resolved
Blocked by: [GitHub-only source policy](01-github-only-policy.md)

## Question

Which GitHub repository and pinned revision corresponds to each remaining direct
SourceHut project input, without contacting SourceHut?

## Answer

GitHub repositories under `averagechris` were verified with GitHub API queries on
2026-09-23. The table records the direct mirror and the revision to carry into a
future lock update. The current revision selected for each of the 13 direct
projects is available from GitHub. This records the mapping; the lock update is
specified separately in [Fourteen-lock rollout and checks](04-fourteen-lock-rollout.md).

| Project | GitHub mirror | Selected pin | Notes |
| --- | --- | --- | --- |
| `ctx` | [`averagechris/ctx`](https://github.com/averagechris/ctx) | `75d4622ef7941a9d23b196d06d29a3d6c7f883cd` | Current lock revision exists on GitHub `main`. |
| `gander` | [`averagechris/gander`](https://github.com/averagechris/gander) | `3c3d674fa4eeab7c47085e9e7617231183d415a8` | Current lock revision exists in the GitHub repository. |
| `granola-cli` | [`averagechris/granola-cli`](https://github.com/averagechris/granola-cli) | `3e92e7fae73e6bf6cbdabe1ef73f035b0f02884b` | Current lock revision exists on GitHub `main`. |
| `hister` | [`averagechris/hister`](https://github.com/averagechris/hister) | `94f4a98d98ba66c28b79ab310780360d533423a2` | Current lock revision exists on GitHub `main`. |
| `linear-cli` | [`averagechris/linear-cli`](https://github.com/averagechris/linear-cli) | `67d9eb1a91525ba4e3fc919dc661b1bfd3fa0bff` | Current lock revision exists on GitHub `main`. |
| `nitter-link` | [`averagechris/nitter-link`](https://github.com/averagechris/nitter-link) | `e627d315a2433dd4170d901a0ea9dbd9dd518784` | Existing `v0.1.4` pin exists on GitHub; do not silently upgrade to `v0.1.5`. |
| `pip-chrome-extension` | [`averagechris/pip-chrome-extension`](https://github.com/averagechris/pip-chrome-extension) | `43a13261589f64e2e6aefedb7ab6b48e47cc00aa` | Current lock revision exists on GitHub `main`. |
| `rdny` | [`averagechris/rdny`](https://github.com/averagechris/rdny) | `2a558f6dbe30b05c04ed2a141958901f07ef3b85` | Current lock revision exists on GitHub `main`. |
| `sideshow` | [`averagechris/sideshow`](https://github.com/averagechris/sideshow) | `78b05ba424bd82595464e3d71ff3aed7af721817` | Current lock revision exists on GitHub `main`. |
| `slack` | [`averagechris/slack`](https://github.com/averagechris/slack) | `faa6651e1ad3d97810148236136392a415a0962b` | Current lock revision exists on GitHub `main`. |
| `srht` | [`averagechris/srht`](https://github.com/averagechris/srht) | `125f982de6fe846c55896cec9b5de746596b872b` | Root current lock revision exists in the GitHub repository. Preserve the package/module interface. |
| `starship-jj` | [`averagechris/starship-jj`](https://github.com/averagechris/starship-jj) | `9181170ac714dc32764243a0a888c9a6a07a022f` | Current lock revision exists on GitHub `main`. |
| `titlecase` | [`averagechris/titlecase`](https://github.com/averagechris/titlecase) | `11e70c1f1d5796c5f7d2930df53cfaa9a1fc2200` | Current lock revision exists on GitHub `main`. |

The map deliberately excludes `averagechris.srht.site`/`fleet` from this direct
set. That is a transitive input covered by the chosen source and follows
topology in [Transitive fleet/site source](03-transitive-fleet-site.md).

The standalone locks do not need separate historical `srht` mappings. Their
older `srht` nodes disappear when the child flakes follow the shared root
`srht` input. The rollout must preserve the package/module interface while
regenerating those locks; it does not depend on claiming that every older
object is present or absent in the GitHub repository.
