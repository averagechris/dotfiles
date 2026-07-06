# srht CLI

The `dotfiles.srht` Home Manager module installs `srht`, the SourceHut CLI for
builds, git, todo, lists, pages, paste, hub, webhooks, and GraphQL workflows.

## Package source

The package comes from the upstream SourceHut flake:

```nix
inputs.srht.url = "sourcehut:~averagechris/srht";
```

The module defaults `dotfiles.srht.package` to
`inputs.srht.packages.${system}.srht` when that input is available. It imports
the upstream `programs.srht` Home Manager module and enables it when
`dotfiles.srht.enable = true`.

## Configuration and completions

The upstream module writes `~/.config/srht/config.toml` from
`programs.srht.instances`. By default it configures the public `sr.ht` instance
and lets `srht` use its normal OS keyring behavior. For headless hosts, set
`tokenCmd` instead of writing plaintext tokens into Nix:

```nix
programs.srht.instances = [
  {
    name = "sr.ht";
    tokenCmd = ["${pkgs.coreutils}/bin/cat" "/run/agenix/srht-token"];
  }
];
```

The package ships bash, fish, zsh completions, and man pages under `share/`.
Adding the package to `home.packages` installs those completions into the Home
Manager profile for the configured shells.

## OpenCode skills

By default, `dotfiles.srht.opencodeSkills.enable = true` runs this during Home
Manager activation:

```bash
srht skills install --dir ~/.config/opencode/skills --force
```

This installs all bundled srht agent skills as OpenCode skills, currently:

- `srht-issues` - todo.sr.ht issue workflows
- `srht-ci` - builds.sr.ht CI submission, following, and logs
- `srht-setup` - auth, config, repository init, and cache refresh setup

Set `dotfiles.srht.opencodeSkills.names` to a list of skill names to install a
subset, or set `dotfiles.srht.opencodeSkills.enable = false` to skip activation
installation.

## Enabled hosts

`suremac`, `tater`, and `thorny` enable `dotfiles.srht`. All three also add
`srht` to `dotfiles.opencode.agentTools`, so OpenCode agents see the SourceHut
CLI in their runtime tool note.

`thorny` configures `programs.srht.instances` with a `tokenCmd` that reads the
existing agenix-managed SourceHut token used by hut. `suremac` and `tater` use
the default keyring-backed srht authentication flow.
