# GPG Agent Lock / keyboxd Timeout

## Symptoms

When running `jj` (or `git` with GPG signing), you see errors like:

```
gpg: Note: database_open 134217901 waiting for lock (held by PID) ...
gpg: keydb_search failed: Connection timed out
gpg: signing failed: Connection timed out
```

Or:

```
gpg failed to sign the data
fatal: failed to write commit object
```

## Cause

The GPG `keyboxd` daemon (or sometimes `scdaemon`) can get stuck holding a lock after a reboot, crash, or unclean shutdown. This prevents new GPG operations from completing.

## Solution (Immediate)

Kill the stuck processes and restart the GPG agent:

```bash
# Kill stuck keyboxd
pkill -9 keyboxd

# Restart gpg-agent
gpgconf --kill gpg-agent
gpgconf --launch gpg-agent
```

Then test:
```bash
jj st  # or git commit
```

## Permanent Fix

The dotfiles now include a systemd service that automatically cleans stale GPG locks on login:

- **Location**: `flakes/hm-modules/modules/gpg.nix`
- **Service**: `gpg-agent-cleanup.service`
- **Runs on**: `graphical-session.target` (when you log in)

This service:
1. Kills any stale `keyboxd` processes
2. Launches `gpg-agent` if needed

It intentionally does **not** kill `gpg-agent` during normal login/profile switches, because `gpg-agent` owns the in-memory passphrase cache. Killing it would force a new passphrase prompt after every switch.

After rebuilding your system, this will happen automatically on each login.

If `gpg-agent-cleanup.service` itself is failing, check its status:

```bash
systemctl --user --no-pager --full status gpg-agent-cleanup.service
```

If you see an error like:

```text
Failed at step EXEC spawning .../bin/pkill: No such file or directory
```

then your currently installed user unit still has the old broken cleanup command. Rebuild and switch your Home Manager or NixOS configuration so the fixed unit from `flakes/hm-modules/modules/gpg.nix` is installed.

## Manual Fix (If systemd service fails)

If the issue persists and you are willing to lose the current passphrase cache:

```bash
gpg-agent-recover
```

This kills stale `keyboxd`, restarts `gpg-agent`, and relaunches it.

## Verification

To verify the cleanup service is enabled:

```bash
systemctl --user status gpg-agent-cleanup.service
```

To verify the installed unit is valid before or after rebuilding:

```bash
systemd-analyze --user verify ~/.config/systemd/user/gpg-agent-cleanup.service
```

## Related Files

- `flakes/hm-modules/modules/gpg.nix` - Contains the cleanup service
- `flakes/nixos-modules/modules/users/chris.nix` - GPG agent configuration
