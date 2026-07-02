# Gander

[`gander`](https://git.sr.ht/~averagechris/gander) is a terminal UI for reviewing
`jj` changes, tracking viewed files, adding lightweight comments, and exporting
review artifacts.

## Home Manager module

The Home Manager module lives at `flakes/hm-modules/modules/gander.nix` and is
imported by the default dotfiles Home Manager module.

```nix
dotfiles.gander.enable = true;
```

When enabled, the module:

- installs `inputs.gander.packages.${system}.default` in `home.packages`
- writes `~/.config/gander/config.toml`
- seeds a Colemak Mod-DH-friendly keybinding layer

The module is currently enabled for `suremac`, `tater`, `thorny`, and `trap`.

## Options

| Option | Purpose |
| --- | --- |
| `dotfiles.gander.enable` | Install and configure Gander. |
| `dotfiles.gander.package` | Package to install. Defaults to the `gander` flake input for the host system. |
| `dotfiles.gander.settings` | Extra TOML settings merged over the dotfiles defaults and written to `~/.config/gander/config.toml`. |

`settings` follows Gander's upstream TOML schema. Use kebab-case keys for
Gander config fields:

```nix
dotfiles.gander.settings = {
  artifact.on_tui_quit = "write";
  generated.presets = ["lockfiles"];
  keybindings.toggle-generated = ["h"];
};
```

Gander also layers project config after the XDG user config, so `gander.toml` or
`.gander/config.toml` in a repository can override these user defaults for that
project.

## Dotfiles keybindings

The module keeps Gander's defaults except where Colemak Mod-DH navigation or
left/right ergonomics are useful.

| Action | Keys |
| --- | --- |
| Next file | `n`, Down |
| Previous file | `e`, Up |
| Target picker down | Down, Ctrl-N |
| Target picker up | Up, Ctrl-E |
| Next unviewed file | `]` |
| Previous unviewed file | `[` |
| Next comment | `l` |
| Previous comment | `L` |
| Collapse fold | `m`, Left |
| Expand fold | `i`, Right |

Notable upstream defaults left intact include Tab to toggle focus, Space to
toggle folds, `t`/`p` to compare against trunk/parent, `h` to hide generated
files, Enter to mark viewed, `c`/`e`/`x` for comments, and `q`/Esc to quit.

## Updating

Gander is a flake input. When bumping it, update each relevant lockfile: the
host lockfiles for enabled hosts, the Home Manager modules lockfile, and the
root aggregator lockfile nodes used by builds from the repository root.
