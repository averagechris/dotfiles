# rdny

rdny is the Rust browser automation CLI used on `suremac` and `tater`. It drives
Chrome-family browsers through the Chrome DevTools Protocol and keeps session
state between commands so agents can navigate, inspect, interact, capture
screenshots, record short videos, and attach to manually launched browsers.

## Package source

Hosts get rdny from the personal flake input:

```nix
inputs.rdny.url = "sourcehut:~averagechris/rdny";
```

The Home Manager module defaults `dotfiles.rdny.package` to
`inputs.rdny.packages.${system}.rdny` when that input is available.

## Home Manager module

Enable rdny with:

```nix
dotfiles.rdny.enable = true;
```

The module installs `rdny`, can write `~/.config/rdny/config.toml`, can expose
the CLI to OpenCode agents, and can install the repo-managed `rdny-browser`
OpenCode skill. The generated config mirrors rdny's user config schema:

```toml
[binaries]
chrome = [
  "/Applications/Helium.app/Contents/MacOS/Helium",
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
]
ffmpeg = "/nix/store/.../bin/ffmpeg"

[connect]
default = "helium"

[connect.targets]
helium = "127.0.0.1:9333"
```

Module options cover rdny's current configuration and environment surface:

- `dotfiles.rdny.binaries.chrome.path` or `.package` selects the first
  `[binaries].chrome` candidate; `.fallbackPaths` appends ordered alternatives.
- `dotfiles.rdny.binaries.ffmpeg.enable` writes `[binaries].ffmpeg`; the default
  package is `pkgs.ffmpeg`.
- `dotfiles.rdny.connect.default` and `.targets` write named `rdny connect`
  targets.
- `dotfiles.rdny.environment.stateDir` optionally exports `RDNY_STATE_DIR`.
- `dotfiles.rdny.environment.chromeArgs` optionally exports `RDNY_CHROME_ARGS`.
- `dotfiles.rdny.settings` merges extra TOML, overriding generated values.

Binary precedence stays rdny-native: environment variables win first, then the
config file, then built-in fallbacks (`RDNY_CHROME`, `RDNY_FFMPEG`,
`RDNY_CONFIG`, and `RDNY_STATE_DIR` are all runtime escape hatches).

## Current upstream behavior

The current rdny build substantially hardens managed sessions. `rdny start` now
launches Chrome behind an authenticated, owner-only local broker using
`--remote-debugging-pipe`; managed sessions no longer expose a DevTools TCP port.
External `rdny connect` targets remain the explicit loopback HTTP/WebSocket path.
Lifecycle state and artifacts use private transactional storage, command
timeouts share one deadline budget, downloads and recordings are bounded, and
machine output is available through global `--format human|json|jsonl` modes.

Configured Chrome executables are now ordered candidates. The module emits the
new array form even for one executable while upstream still accepts the old
single string for compatibility. Failed configured candidates fall through to
rdny's platform discovery.

## Host enablement

- `suremac` enables rdny, points `[binaries].chrome` at the manually installed
  Helium app, enables ffmpeg for video assembly, configures a `helium` connect
  target at `127.0.0.1:9333`, and exposes rdny plus the `rdny-browser` skill to
  OpenCode agents.
- `tater` enables rdny, points `[binaries].chrome` at the Home Manager Helium
  package, enables ffmpeg, configures the same `helium` connect target, and
  exposes rdny plus the `rdny-browser` skill to OpenCode agents.

To use the named personal-browser target, launch the browser with a CDP debug
port first:

```bash
open -na Helium --args --remote-debugging-port=9333 --user-data-dir=/tmp/rdny-helium
rdny connect helium
```

On Linux, launch the configured browser binary with the same
`--remote-debugging-port=9333` flag and a non-default user data directory when
Chromium ignores the debug port on the default profile.

## Useful commands

```bash
rdny start --label agent
rdny status
rdny open https://example.com
rdny title
rdny --format json status
rdny html 'main'
rdny text 'h1'
rdny js -
rdny screenshot page.png
rdny start-video
rdny stop-video recording.mp4
rdny stop
```

Use `rdny --state-dir <dir> ...` when you need an isolated session separate from
the default state directory.
