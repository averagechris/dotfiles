# Yazi

Yazi is configured by the Home Manager shell module at
`flakes/hm-modules/modules/shell-modules/yazi.nix`.

## Module behavior

- Enable with `dotfiles.shell.yazi.enable = true` or the legacy
  `dotfiles.yazi.enable = true` wiring from the shell module.
- The shell wrapper name is pinned to `yy` with
  `programs.yazi.shellWrapperName = "yy"` to preserve the pre-26.05 wrapper
  behavior.
- Keybindings are Colemak-oriented: `m` leaves to the parent directory, `n`
  moves down, `e` moves up, and `i` enters directories.
- The theme is loaded from
  `flakes/hm-modules/modules/shell-modules/yazi-theme/rose-pine-moon.toml`.

## Theme rule schema

Yazi 26.5+ requires each `[filetype].rules` entry to specify either `mime` or
`url`. Do not use `name` in filetype rules; `name` is valid for icon rules, not
filetype styling rules. For filename/path-based filetype styling, use `url`
globs such as:

```toml
[filetype]
rules = [
  { mime = "image/*", fg = "#ebbcba" },
  { url = "**/flake.nix", fg = "#31748f", bold = true },
  { url = "**/*.nix", fg = "#31748f" },
]
```

If `yazi` fails at startup with `at least one of url or mime must be specified`,
check for stale `name = ...` entries under `[filetype].rules`.
