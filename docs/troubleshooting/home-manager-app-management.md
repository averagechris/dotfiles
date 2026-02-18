# Home Manager App Management permission fails on macOS

## Symptoms

- `darwin-rebuild switch` fails during home-manager activation with:
  `permission denied when trying to update apps`
- System Settings > Privacy & Security > App Management does not keep your terminal emulator

## Cause

Home Manager's macOS app copying uses `targets.darwin.copyApps` and checks the
**App Management** TCC permission. If your terminal emulator is installed from
the Nix store (e.g., WezTerm via Nix), the app bundle path changes between
rebuilds and macOS removes the permission.

## Fix (dotfiles recommended for Nix-installed terminals)

Disable the App Management check for the affected host:

```nix
home-manager.users.chris = {
  targets.darwin.copyApps.enableChecks = false;
};
```

This keeps app copying enabled but skips the permission check.

## Alternative

Run `darwin-rebuild` from a stable, system-installed terminal app (like
`/System/Applications/Utilities/Terminal.app`) and grant App Management to that
app. This only works reliably if the terminal app path is stable (non‑Nix).

## Related Issue: rsync permission denied in Home Manager Apps

If you see errors like:

```
rsync: [generator] failed to set permissions on "~/Applications/Home Manager Apps/.": Permission denied (13)
rsync: [generator] delete_file: unlink(WezTerm.app) failed: Permission denied (13)
```

The `~/Applications/Home Manager Apps` directory (or app bundles inside it)
may be owned by `root` from a previous activation run. Reset the directory
ownership and re-run the switch:

```bash
sudo rm -rf "/Users/chris/Applications/Home Manager Apps"
sudo mkdir -p "/Users/chris/Applications/Home Manager Apps"
sudo chown -R chris:staff "/Users/chris/Applications/Home Manager Apps"
```
