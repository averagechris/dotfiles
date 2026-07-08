# suremac macOS Configuration

`suremac` is the Darwin/macOS host configured in `flakes/hosts/suremac/`.

## LAN SSH

`suremac` enables macOS Remote Login through nix-darwin so local NixOS machines
can SSH in on trusted LANs. It authorizes thorny's `chris.thelio` user key and
tater's `system.tater` host key; see [LAN SSH](/docs/lan-ssh.md) for the
DHCP-friendly `dotfiles-lan-hosts`, `ssh-lan`, and `ssh-suremac-lan` helpers and
for the current key-trust caveat around a future dedicated `chris@tater` user key.

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

## Colemak Mod-DH Keyboard Layout

`suremac` enables `dotfiles.colemakDh`, the first shared nix-darwin module in
`flakes/darwin-modules/`. The module vendors the ColemakMods Mod-DH keyboard
layout bundle and installs it during activation (via the `extraActivation`
fragment; nix-darwin only runs its fixed set of activation fragments) at the
system-wide path:

```text
/Library/Keyboard Layouts/Colemak mDH.bundle
```

Installing the bundle under `/Library/Keyboard Layouts` makes it available at the
macOS login screen, not only after the primary user logs in. Activation compares
the vendored bundle with the installed copy before replacing it, then normalizes
ownership and permissions to root-owned, world-readable bundle contents.

The module configures both login-window and primary-user HIToolbox preferences to
prefer **Colemak DH ANSI - Extended** (`KeyboardLayout ID = -25869`, input source
ID `io.github.colemakmods.keyboardlayout.colemakdh.colemakdhansi-extended`) while
keeping **U.S.** enabled as a fallback. Both levels are seed-once: if the
respective `com.apple.HIToolbox` domain already lists the Colemak input source,
rebuilds leave that domain alone, so runtime input-source changes and manually
added layouts are not reset on every build. Writes go through `defaults` (user
level additionally via `launchctl asuser`) rather than editing plist files, to
avoid stale `cfprefsd` cache flushes.

HIToolbox and keyboard-layout cache changes may require logging out and back in,
or waiting for/restarting `cfprefsd`, before every UI surface notices the new
layout. The module does not kill `cfprefsd` during activation.

## Terminal Hotkey

`suremac` explicitly enables the Home Manager WezTerm module with
`dotfiles.wezterm.enable = true` and sets `dotfiles.gui.terminal` to WezTerm.
The host disables the old `skhd` macOS hotkey agent and disables the Kitty
terminal module, keeping the Home Manager closure focused on the one terminal in
active use.

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

These hotkeys are historical notes only while `dotfiles.macosHotkeys.enable` is
disabled on suremac.

## Raycast Configuration

Raycast does not expose a stable declarative config file for aliases and
hotkeys. Use Raycast's built-in sync for Raycast-managed configuration instead
of committing `.rayconfig` exports to this repository.

## Coding Agents

`suremac` enables both `programs.opencode` and `programs.pi` in Home Manager.
Pi is installed through the minimal `programs.pi.enable = true` module; see
[`docs/pi.md`](/docs/pi.md) for the package pinning and manual update policy.

OpenCode agents on `suremac` also get host-specific CLI tools, including
`awscli2` as `aws` and `ctx` for local agent-history search. CircleCI and
CodeRabbit tooling are not configured because work has migrated away from those
services.

The Datadog Pup CLI is installed in Home Manager as `pup` and exposed to
OpenCode agents as a host-specific Datadog tool. `suremac` also installs the
`pup-cli` OpenCode skill so agents use bounded, filtered Pup output instead of
dumping large Datadog payloads. See [`docs/pup.md`](/docs/pup.md) for packaging,
credential, agent-usage, and update notes.

## Daily dotfiles Self-Update

`suremac` runs a nix-darwin launchd user agent named
`dotfiles-suremac-self-update`. The agent wakes hourly (`StartInterval = 3600`,
plus `RunAtLoad`) but the script attempts at most one update per ~23 hours,
tracked in `~/.local/state/dotfiles-self-update/last-run`. This way a missed
update window (laptop asleep or powered off) is caught up the next time the
machine is running, instead of waiting for a fixed wall-clock time. It is a
user agent, not a daemon, so it runs in the Aqua login session and can display
macOS notifications and password dialogs.

The job keeps a dedicated public HTTPS clone of the canonical dotfiles remote at
`~/.local/state/dotfiles-self-update/repo`. Each run fetches `main`, hard-resets
the clone to `origin/main`, builds
`darwinConfigurations.suremac.system` with an out-link at
`~/.local/state/dotfiles-self-update/result`, and compares the built store path
to `/run/current-system`. If the paths match, it exits quietly without a
notification or password prompt.

The daily throttle stamp is written after a successful build: transient
fetch/build failures retry silently on the next hourly wake, while a no-op, a
successful activation, or a cancelled password prompt all count as the daily
attempt so at most one password dialog appears per day.

When a new system was built, the job posts a notification and activates the
pre-built closure with sudo. The sudo password prompt is a small nix-managed
askpass helper that calls `/usr/bin/osascript` with a hidden-answer GUI dialog;
the job sets `SUDO_ASKPASS` and runs sudo with `-A`, so activation can happen
from launchd without a terminal. Cancelling the dialog or failing activation
posts a failure notification and leaves details in the log.

Logs are written to `~/Library/Logs/dotfiles-self-update.log`.

When an update changes the self-update agent itself, activation reloads the
launchd job that is running the update, killing the script after activation
succeeds but before it can report the outcome. A companion agent,
`dotfiles-self-update-notify`, closes that gap: the self-update script writes a
pending-activation marker (`~/.local/state/dotfiles-self-update/pending-activation`)
just before activating and removes it when it reports inline. The notify
agent's plist embeds a hash of the self-update agent's configuration, so
nix-darwin reloads it (firing `RunAtLoad`) in exactly the self-restart
scenario; it then polls `/run/current-system` until the marker's target system
is live and posts the success notification the killed run could not. Stale
markers (unconfirmed for over two hours) produce a failure notification
instead, and every self-update run also reconciles leftover markers at
startup. `WatchPaths` on `/run/current-system` cannot be used for this:
launchd's kqueue watch follows the symlink to its target, so replacing the
symlink never triggers it.

Trust model: the job builds and activates whatever `origin/main` points at,
without commit signature verification, gated only by the sudo password dialog.
Anyone who can push to the SourceHut repo can therefore change this host at the
next daily window. This matches the posture of the NixOS `selfDeploy` module;
revisit (for example with `git verify-commit` against a pinned key) if push
access to the repo ever broadens.

Useful manual commands:

```bash
# Trigger the launchd job now for the logged-in user.
launchctl kickstart -k gui/$(id -u)/org.nixos.dotfiles-suremac-self-update

# Run the same script directly, which is useful while watching the log.
# --force bypasses the ~23h throttle.
dotfiles-suremac-self-update --force
```

To disable the job, remove or comment out `./self-update.nix` from
`flakes/hosts/suremac/configuration.nix` and rebuild/switch the host. For a
temporary local pause, unload the user agent with `launchctl bootout` for the
same `gui/$(id -u)/org.nixos.dotfiles-suremac-self-update` label; the next
nix-darwin activation may load it again.

## Notion CLI

`suremac` installs the Nix-packaged Notion CLI as `ntn` in
`environment.systemPackages` and exposes it to OpenCode agents as a host-specific
tool. See [`docs/notion-cli.md`](/docs/notion-cli.md) for usage and update notes.

## Personal SourceHut CLIs

`suremac` installs two personal CLIs from SourceHut flake inputs:

- `slack` (`sourcehut:~averagechris/slack`) - Slack CLI, installed in Home
  Manager `home.packages`
- `ctx` (`sourcehut:~averagechris/ctx`) - agentic context CLI for indexing and
  searching coding-agent session history, exposed to OpenCode agents via
  `dotfiles.opencode.agentTools` (also installed on `tater`)

Both follow the host flake's `nixpkgs` and `flake-utils`. Bump them with
`nix flake update slack ctx` in `flakes/hosts/suremac` (and `ctx` in
`flakes/hosts/tater`), plus the matching nested nodes in the root `flake.lock`.

## Sure Tools via `nix profile`

Private sureapp flakes (`surecraft-cli`, `suremise`) are installed
imperatively with `nix profile` because they need GitHub auth at fetch time and
update on their own cadence. Run `install-sure-tools` (a helper installed by
`flakes/hosts/suremac/aws.nix`) to install or refresh them, and
`nix profile upgrade <name>` to bump individual tools. `devenv` also stays a
profile install (`nix profile install nixpkgs#devenv`) to keep its bundled Nix
out of the system closure, while `kubernetes-helm` is managed in Home Manager
`home.packages`.

## Non-Nix GUI Apps

Some GUI apps are intentionally unmanaged. Kandji ("Iru" MDM) pushes or offers
company software (Falcon, SDM, Zoom, Office, Chrome, etc.) via Iru Self
Service. The following are installed manually from upstream and self-update:

- Raycast (uses its own settings sync)
- Helium browser
- superwhisper
- OrbStack
- Logi Options+

## Profile Size Notes

The suremac profile intentionally avoids several large or duplicate GUI/TUI
tools that are not in active use:

- Firefox/Firefox Developer Edition are not managed here; Helium is the active
  browser preference and browser apps can be installed outside Nix when needed.
- Ranger is disabled because Yazi is the maintained terminal file manager in the
  shell module, and Ranger's preview stack pulls a large ImageMagick closure.
- Kitty is disabled because WezTerm is the configured terminal and hotkey target.
- Raycast, Postman, K9s, skhd, CircleCI CLI/token, and Databricks CLI are not
  managed by this host profile; use the upstream Raycast install, ad hoc API
  tools, agentic `kubectl` workflows, and project-local Databricks tooling
  instead.

The Darwin system and Home Manager Git configuration use `gitMinimal` for normal
CLI Git, signing, and jj interoperability. The full nixpkgs Git output currently
retains Python and the Darwin compiler/SDK toolchain on macOS; keep using
`gitMinimal` unless a specific full-Git feature is required.

Helix uses the shared curated grammar runtime documented in
[`docs/helix.md`](/docs/helix.md), covering daily Rust/Python/Nix/shell,
web-development, and cloud/config formats while dropping the upstream long tail
of rarely used grammars such as C/C++ and niche languages.

WezTerm remains the active terminal and Home Manager-managed app. On Darwin, the
cached nixpkgs WezTerm output embeds the absolute `clang-wrapper` path in OpenSSL
compiler metadata inside the app binaries, which otherwise keeps the large
clang/LLVM/Apple SDK closure alive even though it is not needed at runtime.
`suremac` therefore installs a copied WezTerm output with only that build-time
compiler reference scrubbed; the app bundle, CLI tools, shell integration,
terminfo propagation, and Home Manager WezTerm configuration are unchanged.

`suremac` keeps app-launcher behavior with a small shell-based trampoline helper
that runs during the nix-darwin and Home Manager activation phases. The helper
rebuilds Spotlight/Launchpad-friendly trampoline apps for symlinked Nix app
directories and refreshes matching Nix-pinned Dock entries when app store paths
change. This avoids pulling a Common Lisp runtime into the host closure.

The helper still uses `dockutil` for Dock relinking. The nixpkgs `dockutil`
binary only needs the system Swift runtime at execution time, but its build
leaves an extra Nix Swift runtime `LC_RPATH` in the binary. `suremac` installs a
copied `dockutil` with that rpath removed; `dockutil --version` still resolves
against system Swift libraries, while the large Swift/clang/Apple SDK closure is
no longer retained.
## Rust and Dev Cache Management

`suremac` enables `dotfiles.devCache` for Rust-heavy development work. See
[dev-cache.md](/docs/dev-cache.md) for the full module documentation
(sccache setup and server supervision, nix GC behavior and the root GC
reminder, cargo-sweep, and Docker pruning).

Host specifics:

- `SCCACHE_CACHE_SIZE=50G`;
- normal cleanup runs every 6 hours instead of daily;
- a low-disk checker runs every 15 minutes and starts cleanup when `/` has less
  than 10 GiB free;
- the pressure cleanup phase runs `nix-collect-garbage -d` plus `nix store gc`,
  tightens Cargo sweeping to artifacts untouched for 1 day, and trims
  OrbStack/Docker builder cache to 10GB when free space is still below the
  threshold;
- normal Nix user-generation and Cargo target retention are 3 days;
- cargo-sweep roots are `~/projects` and `~/sureapp` (recursive, so managed jj
  workspaces under `~/projects/ws/` and `~/sureapp/ws/` are covered);
- the Docker phase prunes OrbStack's daemon with `pruneVolumes = true`:
  volumes attached to running containers are kept, but stopped development
  stacks may lose local database/queue state on the next cleanup run;
- logs: `~/Library/Logs/sccache-server.log` and
  `~/Library/Logs/dev-cache-cleanup.log`.

Because the cleanup job runs unprivileged, root-owned darwin system profile
generations are never garbage collected automatically; the job posts a macOS
notification when they pile up, and the manual command it suggests keeps the
most recent generations so the immediately previous darwin profile always
remains a rollback target.
