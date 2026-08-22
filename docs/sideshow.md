# Sideshow

Sideshow is the Rust CLI for agent-authored HTML slide decks. It builds a deck
source directory into one self-contained HTML file and supports static checks,
image/video optimization helpers, VHS tape rendering, local serving, and S3 or
SourceHut Pages publishing.

The current release also supports deterministic subsetting and embedding of
deck-declared TrueType font faces, opt-in browser launch for local serving, and a
local review mode with durable point/region annotations and agent handoff
exports. Review state stays under XDG state rather than entering deck source or
built HTML.

## Package source

Hosts get the package from the upstream flake input:

```nix
inputs.sideshow.url = "sourcehut:~averagechris/sideshow";
```

The Home Manager module defaults `dotfiles.sideshow.package` to
`inputs.sideshow.packages.${system}.sideshow` when that input is available.
Hosts without the input can set `dotfiles.sideshow.package` explicitly.

## Home Manager module

Enable the module with:

```nix
dotfiles.sideshow.enable = true;
```

The module installs `sideshow`, writes `~/.config/sideshow/config.toml` by
default, and can expose the CLI to OpenCode agents. The generated config mirrors
sideshow's user config schema:

```toml
[tools]
tailwindcss = "/nix/store/.../bin/tailwindcss"
ffmpeg = "/nix/store/.../bin/ffmpeg"
vhs = "/nix/store/.../bin/vhs"
aws = "/nix/store/.../bin/aws"

[srht]
token-cmd = ["pass", "show", "srht/pages-token"]
```

`tailwindcss` is enabled by default because `sideshow build` shells out to the
Tailwind v4 standalone binary. The module uses nixpkgs' `tailwindcss_4` package;
override `dotfiles.sideshow.tools.tailwindcss.package` or `.path` if a deck needs
a newer/different binary before nixpkgs catches up. Optional helpers can be
enabled per host:

```nix
dotfiles.sideshow.tools.ffmpeg.enable = true;
dotfiles.sideshow.tools.vhs.enable = true;
dotfiles.sideshow.tools.aws.enable = true;
```

The ffmpeg tool defaults to `pkgs.ffmpeg-headless`, shared with rdny and the
Calibre utilities so Home Manager has only one `bin/ffmpeg` provider.

For secrets, do not place plaintext tokens in Nix. Use `SRHT_TOKEN` at runtime or
set `dotfiles.sideshow.srht.tokenCommand` to a keyring/password-manager command.
`suremac` sets this to read the same macOS Keychain item that the `srht` CLI uses
after `srht auth login`: generic password `service = srht`, `account = sr.ht`.

## Host enablement

- `suremac` enables `dotfiles.sideshow`, configures `ffmpeg` for video
  optimization, configures `aws` for S3 publishing, configures sideshow's
  SourceHut Pages token command to read the `srht` Keychain item, and exposes
  `sideshow` to OpenCode agents.
- `tater` enables `dotfiles.sideshow` with the default Tailwind configuration and
  exposes `sideshow` to OpenCode agents. Its story evidence gathering is centered
  on `srht` and the todo.sr.ht tracker rather than Linear.

The module registers two skills with the shared `dotfiles.agentSkills` renderer.
The selected Sideshow package's upstream source provides
`sideshow-deck-author`; the module deploys its complete skill directory, so
companion files such as `fragment-patterns.md` remain available and future
companions are included automatically. An audited bundle manifest requires the
upstream source to contain exactly that registered skill until additions are
reviewed. Package overrides without a `src` attribute skip this upstream
registration.

The separate `sideshow-work-story` skill remains repo-managed. It nudges agents
to collect bounded evidence from `ctx`, Linear, GitHub PRs, and local VCS before
turning the work into an impact narrative or deck. Both skills are enabled by
default and support the per-skill `enable`, `patches`, and `extraText` controls
documented in [`docs/opencode.md`](/docs/opencode.md).

## Useful commands

```bash
sideshow themes --format json
sideshow new ./deck --theme signal
sideshow check ./deck
sideshow build ./deck
sideshow serve ./deck --open --port 0
sideshow serve ./deck --review --open --port 8000
sideshow review export ./deck --format markdown
sideshow publish ./deck --target srht --domain averagechris.srht.site
```

Custom fonts are deck-local rather than Home Manager configuration. Declare
individual `.ttf` faces with `[[fonts]]` entries in `deck.toml`; Sideshow rejects
unsupported outlines or embedding restrictions, preserves licensing metadata,
and charges generated subsets against the existing asset budgets.

For visual QA, build the deck, open the exact printed HTML path in a browser, and
run the deck runtime's `sideshow.audit()` API through browser automation when
available.
