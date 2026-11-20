# T3 Code

Home Manager installs the upstream stable T3 Code desktop on `thorny`,
`tater`, `suremac`, and `taro`. The `t3-code-nix` flake packages the official
[T3 Code releases](https://github.com/pingdotgg/t3code/releases) for Apple
Silicon and x86-64 Linux. Open T3 Code from the desktop launcher or run
`t3code`. The desktop app starts its own local backend. The packaged launcher disables
in-app update checks. On macOS, activation sets the same flag for the current
login session.

The shared Home Manager module enables the OpenCode provider and sets its binary
path to the host's existing `programs.opencode.package`. Upstream T3 Code
requires OpenCode 2.0.18 or newer for its OpenCode 2 integration. Authenticate
OpenCode on each host before starting threads. Home Manager merges the provider
settings into `~/.t3/userdata/settings.json` during activation.

On `suremac`, the [Codex module](codex.md#desktop-cli-on-path) puts the ChatGPT
app's bundled CLI on the session PATH. Restart T3 Code after activation so
its backend picks up the path. For an existing Codex provider with a custom
**Binary path**, use the bundled CLI at
`/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex`.

On `suremac`, this replaces the fork desktop and its separate OpenCode 2.0.8
pin. On first launch, upstream T3 Code copies existing thread history into its
new database. The first new message in an imported thread starts a fresh
provider session with context from that history. See the
[T3 Code migration notes](https://github.com/pingdotgg/t3code/issues/14871).

Update the stable package by refreshing the `t3-code-nix` input in the root
flake and the four standalone host flakes. Keep the packaging revision
consistent across their locks and the input following the shared nixpkgs pin.
Build the target before activation using the [deployment guide](deploy.md).
