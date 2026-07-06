# tom

`tom` is the NixOS host for Home Assistant and Calibre-Web.

`tom` intentionally does not import the shared `desktopCommon` module. It is a
headless service host, so keeping bootloader, OpenSSH, timezone, and time-sync
settings host-local avoids retaining workstation defaults such as graphics,
printing, and GUI-oriented system packages in the runtime closure.

After removing `desktopCommon`, the patched `tom` system closure measured on
`thorny` dropped from about 5.2 GiB to 4.2 GiB. The remaining largest application
closures are Home Assistant and Calibre-Web; the remaining firmware closure comes
from the hardware profile and should only be trimmed after confirming the real
device does not need the firmware or microcode it enables.

## Deployment

Deploy from the repository root with deploy-rs:

```bash
nix run .#deploy -- .#tom
```

When deploying from a local machine that should avoid building the host closure
itself, pass the preferred remote builder through to Nix after the deploy target:

```bash
nix run .#deploy -- .#tom -- --builders 'ssh-ng://chris@thorny x86_64-linux - 8 1 benchmark,big-parallel,kvm,nixos-test'
```

`tom` is also enrolled in the pull-based `dotfiles.selfDeploy` module. It waits
90 minutes after boot, then checks every six hours with a 30-minute randomized
delay. This stagger gives `thorny` time to warm the current `tom` system closure
before `tom` tries to activate it.

The self-deploy service waits up to five minutes for each of these units to be
active after activation, and rolls back to the previous system if they are not:

- `sshd.service`
- `tailscaled.service`
- `nix-daemon.service`
- `home-assistant.service`
- `postgresql.service`
- `calibre-web.service`

Useful checks on `tom`:

```bash
systemctl status dotfiles-tom-self-deploy.timer
systemctl status dotfiles-tom-self-deploy.service
journalctl -u dotfiles-tom-self-deploy.service
```

Manual deploy-rs remains available for immediate deploys or recovery.

## Calibre-Web package note

`tom` applies a host-local overlay to relax Calibre-Web's `requests` runtime
dependency metadata. The upstream `0.6.27b0` wheel currently declares
`requests < 2.33`, while nixpkgs provides `requests 2.33.1`; without the overlay,
the Python runtime dependency check fails during deployment.

Book upload remains enabled, but Calibre-Web book conversion is intentionally
disabled. The current web UI is only used for browsing/serving the library, and
conversion pulls the full Calibre runtime into `tom`'s system closure. If web-side
conversion becomes important again, prefer revisiting this as part of a future
Calibre-Web fork or package customization rather than casually re-enabling the
large default conversion closure.
