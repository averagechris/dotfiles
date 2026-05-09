# tom

`tom` is the NixOS host for Home Assistant and Calibre-Web.

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

## Calibre-Web package note

`tom` applies a host-local overlay to relax Calibre-Web's `requests` runtime
dependency metadata. The upstream `0.6.27b0` wheel currently declares
`requests < 2.33`, while nixpkgs provides `requests 2.33.1`; without the overlay,
the Python runtime dependency check fails during deployment.
