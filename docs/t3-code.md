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

On `suremac` and `tater`, the shared module instead points T3 Code at an
OpenCode launcher. The launcher reads the existing owner-only agenix OpenRouter
key file when T3 starts OpenCode and exports `OPENROUTER_API_KEY` only to that
process. The Nix store contains the key file path, never the key value. A
missing or empty key makes the launcher fail without printing the value.
Other hosts continue to use the OpenCode package directly.

`suremac` also declares its worktree default and idle-compaction preferences.
It clears the previously configured external OpenCode URL so T3 starts its own
OpenCode server and actually uses the launcher. T3 retains the existing server
password in its separate secret store. Home Manager's mutable
settings merge preserves other T3 preferences and per-project overrides.
These declared fields win again on the next activation if changed in the UI.
Model choices, project overrides, and client appearance remain UI-owned.
The sensitive `OPENROUTER_API_KEY` row previously added in T3's UI is no
longer needed for OpenCode processes launched through the wrapper; it can be
removed after confirming the new configuration works.

After activating a changed T3 Code configuration, fully quit and reopen the
desktop app before testing a fresh OpenCode thread. An existing thread may
still refer to its previous external server session. Test resumption
separately before relying on it. A successful provider status check only
proves that OpenCode started; run a small OpenRouter completion to verify
credential delivery. Confirm the configured Experiential Labs models still
appear in T3's model picker after switching to the managed server.
If T3 shows a generic OpenCode CLI health-check error, run its configured
OpenCode launcher with `--version` in a terminal to see the specific key-file
error.

Before the first activation that clears the external server settings, keep a
private backup of the mutable settings file:

```bash
umask 077
cp -n ~/.t3/userdata/settings.json ~/.t3/userdata/settings.before-managed-opencode.json
```

Rolling back a Home Manager generation does not restore that URL because
the older declaration leaves it unspecified. If the external server is
needed again, quit T3 Code fully, restore the backup to
`~/.t3/userdata/settings.json`, keep its mode `0600`, and reopen T3 Code.
The backup can contain sensitive provider settings; keep it out of the repo.
T3 keeps provider passwords in a separate secret store, so the JSON backup
does not recover a password changed or removed independently in T3's UI.

On `suremac`, this replaces the fork desktop and its separate OpenCode 2.0.8
pin. On first launch, upstream T3 Code copies existing thread history into its
new database. The first new message in an imported thread starts a fresh
provider session with context from that history. See the
[T3 Code migration notes](https://github.com/pingdotgg/t3code/issues/14871).

Update the stable package by refreshing the `t3-code-nix` input in the root
flake and the four standalone host flakes. Keep the packaging revision
consistent across their locks and the input following the shared nixpkgs pin.
Build the target before activation using the [deployment guide](deploy.md).
