# suremac macOS Configuration

`suremac` is the Darwin/macOS host configured in `flakes/hosts/suremac/`.

## Time Zone

`suremac` does not pin `time.timeZone` to a fixed IANA zone. Instead, the host
leaves `time.timeZone = null`, enables macOS's automatic time zone preference
(`com.apple.timezone.auto`), and turns on network time during activation. This
lets macOS update the system time zone from the current location after the Mac
has network/location data.

If automatic time zone updates do not take effect after applying the config,
check **System Settings → Privacy & Security → Location Services → System
Services** and make sure time zone/location services are allowed.

## Spaces / Desktops

Mission Control desktop switching is configured with stable Space ordering:

- `system.defaults.dock.mru-spaces = false` keeps Spaces from reordering by most-recent use.
- `system.defaults.spaces.spans-displays = false` keeps each display's Spaces separate.

The host also enables the standard macOS desktop switching shortcuts through
`com.apple.symbolichotkeys` so keyboard-synthesizing tools such as Logi Options
can trigger them reliably:

| Shortcut | Action |
| --- | --- |
| `Control+Left Arrow` | Move left a Space / previous desktop |
| `Control+Right Arrow` | Move right a Space / next desktop |

These are intentionally arrow-key shortcuts rather than letter shortcuts because
letter-based Mission Control hotkeys can be layout-sensitive under Colemak and
may not be reproduced correctly by external device software.

## Terminal Hotkey

`suremac` runs `skhd` as a Home Manager launchd agent for global macOS hotkeys.
It explicitly enables the Home Manager WezTerm module with
`dotfiles.wezterm.enable = true` and sets `dotfiles.gui.terminal` to WezTerm,
so the WezTerm app/config and the global terminal hotkey stay in sync.

| Shortcut | Action |
| --- | --- |
| `Command+Option+T` | Focus the configured dotfiles terminal, or launch it if it is not running |
| `Command+Option+B` | Focus a running browser, or open the default browser if none is running |
| `Command+Option+S` | Capture a selected screenshot region directly to the clipboard |
| `Command+Option+[` | Previous tab, emitted as `Command+Shift+[` |
| `Command+Option+]` | Next tab, emitted as `Command+Shift+]` |
| `Command+Option+N` | Mission Control (`N` is the Colemak-DH vertical-up key) |
| `Command+Option+E` | App Exposé (`E` is the Colemak-DH vertical-down key) |
| `Command+Option+Escape` | Lock screen |

The terminal target is derived from `dotfiles.gui.terminal`, so changing the
configured terminal package from WezTerm to Ghostty (or another terminal) also
changes what this hotkey focuses/launches. The helper uses the macOS app name
for known terminals (`WezTerm`, `Ghostty`) and the configured terminal command
for launching.

The browser hotkey prefers focusing an already-running browser from a known list
(Safari, Chrome, Firefox, Helium, Arc, Brave, Edge). If none are running, it
falls back to `open about:blank`, which launches the system default browser.

`skhd` requires macOS Accessibility permission. If the shortcut does nothing
after applying the config, enable `skhd` in **System Settings → Privacy &
Security → Accessibility** and restart the `skhd` launchd agent or log out and
back in.

## Raycast Configuration

Raycast does not expose a stable declarative config file for aliases and
hotkeys. Use Raycast's built-in sync for Raycast-managed configuration instead
of committing `.rayconfig` exports to this repository.

## Coding Agents

`suremac` enables both `programs.opencode` and `programs.pi` in Home Manager.
Pi is installed through the minimal `programs.pi.enable = true` module; see
[`docs/pi.md`](/docs/pi.md) for the package pinning and manual update policy.

OpenCode agents on `suremac` also get host-specific CLI tools, including
`awscli2` as `aws` and the Nix-packaged CodeRabbit CLI as `coderabbit` / `cr`. See
[`docs/coderabbit-cli.md`](/docs/coderabbit-cli.md) for the local review
workflow and the Nix update policy.

The Datadog Pup CLI is installed in Home Manager as `pup` and exposed to
OpenCode agents as a host-specific Datadog tool. `suremac` also installs the
`pup-cli` OpenCode skill so agents use bounded, filtered Pup output instead of
dumping large Datadog payloads. See [`docs/pup.md`](/docs/pup.md) for packaging,
credential, agent-usage, and update notes.

## Notion CLI

`suremac` installs the Nix-packaged Notion CLI as `ntn` in
`environment.systemPackages` and exposes it to OpenCode agents as a host-specific
tool. See [`docs/notion-cli.md`](/docs/notion-cli.md) for usage and update notes.

## Personal SourceHut CLIs

`suremac` installs two personal CLIs from SourceHut flake inputs in Home
Manager `home.packages`:

- `slack` (`sourcehut:~averagechris/slack`) - Slack CLI
- `ctx` (`sourcehut:~averagechris/ctx`) - agentic context CLI for indexing and
  searching coding-agent session history (also installed on `tater`)

Both follow the host flake's `nixpkgs` and `flake-utils`. Bump them with
`nix flake update slack ctx` in `flakes/hosts/suremac` (and `ctx` in
`flakes/hosts/tater`), plus the matching nested nodes in the root `flake.lock`.

## Rust and Dev Cache Management

`suremac` enables `dotfiles.rustDevCache` for Rust-heavy development work:

- installs `sccache` and configures Cargo with `rustc-wrapper = "sccache"`;
- sets `SCCACHE_DIR=~/.cache/sccache` and a generous `SCCACHE_CACHE_SIZE=50G`;
- installs the Docker CLI for cleanup tasks; and
- runs a daily user launchd job named `dev-cache-cleanup`.

The launchd job writes logs to `~/Library/Logs/dev-cache-cleanup.log`. It starts
or refreshes the local `sccache` server with the configured cache limit, then
uses Docker/OrbStack's Docker socket to prune old builder cache, stopped
containers, dangling images, and unused networks older than 14 days while keeping
Docker builder cache under about 30 GB. On `suremac`, `pruneVolumes = true` also
prunes unused Docker volumes; volumes attached to running containers are kept,
but stopped development stacks may lose local database/queue state on the next
cleanup run.

Per-project Cargo `target/` directories can still grow large, especially from
debug incremental artifacts. Deleting a stale `target/` directory is safe when a
project is not actively building; the next build will recompile and reuse
`sccache` where possible.
