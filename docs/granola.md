# Granola CLI

The `dotfiles.granola` Home Manager module installs `granola`, the Rust CLI for
Granola meeting notes, folders, transcripts, and exports.

## Package source

`suremac` provides the package from the upstream SourceHut flake:

```nix
inputs.granola-cli.url = "sourcehut:~averagechris/granola-cli";
```

The module defaults `dotfiles.granola.package` to
`inputs.granola-cli.packages.${system}.default` when that input is available.
Hosts that do not provide the input can leave the module disabled or set
`dotfiles.granola.package` explicitly.

When bumping the CLI, update both the standalone `suremac` host lock and the
top-level aggregator lock so `nh darwin build ./flakes/hosts/suremac --hostname
suremac` and `nh darwin build . --hostname suremac` resolve the same revision.

## Authentication

Granola credentials are stored by the CLI in the OS keyring (`granola-cli` /
`default`). Plaintext credential config is intentionally not managed.

On `suremac`, the API token is checked in as `secrets/granola-token.age`,
decrypted by agenix to `/run/agenix/granola-token`, and used only during Home
Manager activation. If `granola auth status --output json --compact` reports no
configured key, activation runs:

```bash
granola auth login --key-stdin --validate --quiet < /run/agenix/granola-token
```

Existing keyring credentials are left alone, so rotating the checked-in token may
require `granola auth logout --force` before the next activation or a manual
`granola auth login --key-stdin --validate`.

## suremac configuration

`suremac` enables the module in Chris's Home Manager configuration and adds
`granola` to `dotfiles.opencode.agentTools`, so OpenCode primary agents see it
in their runtime tool note and get the package in their PATH.

Other hosts import the shared Home Manager module set but do not enable
`dotfiles.granola` and do not receive the package or token.
