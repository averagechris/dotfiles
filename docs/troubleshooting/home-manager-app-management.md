# Home Manager App Management permission fails on macOS

Home Manager copies managed apps into `~/Applications/Home Manager Apps` during
a Darwin switch. macOS can block updates to an existing signed app even when
your account owns it. If `copyApps` reports `Operation not permitted (1)` and
rsync exits with code 23, check the directory and app named in the error. For
example, on suremac:

```bash
ls -ledO@ "$HOME/Applications/Home Manager Apps" \
  "$HOME/Applications/Home Manager Apps/T3 Code (Beta).app"
```

Open Apple's Terminal, enable it under **System Settings → Privacy & Security
→ App Management**, then quit and reopen Terminal. Retry the switch from your
dotfiles checkout. Use your host name, such as `suremac`:

```bash
nh darwin switch . --hostname suremac
```

Terminal has a stable installation path. macOS can drop an App Management
grant when a Nix-installed terminal moves to a new store path.

If Terminal still reports code 23 for one app, quit that app and use Finder to
move just the affected bundle out of `Home Manager Apps` to a backup location.
Retry the switch and verify the replacement launches. For T3 Code, thread
history and settings live under `~/.t3`.

On suremac, `targets.darwin.copyApps.enableChecks = false` skips Home Manager's
preflight probe. macOS still enforces App Management during the copy.

If rsync reports `Permission denied (13)`, check the owner of `Home Manager
Apps` and the affected bundle. If the directory is root-owned, restore its
ownership so rsync can create and remove entries:

```bash
sudo chown "$(id -un):$(id -gn)" "$HOME/Applications/Home Manager Apps"
```

If the affected bundle is a root-owned directory, restore its ownership before
retrying:

```bash
sudo chown -R "$(id -un):$(id -gn)" "$HOME/Applications/Home Manager Apps/<affected app>.app"
```
