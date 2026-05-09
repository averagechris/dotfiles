# Shell configuration

## Zsh module

The Home Manager Zsh module lives at `flakes/hm-modules/modules/shell-modules/zsh.nix`.
It enables the Zsh configuration used across hosts, including aliases, history
settings, and environment setup.

### PATH precedence

The Zsh config prepends `~/.nix-profile/bin` to `PATH` so profile overrides take
priority over Home Manager `home.packages`. This makes it easy to temporarily
install newer versions in a profile and have them win by default.

```
export PATH="$HOME/.nix-profile/bin:$PATH"
```

## direnv

The shell module enables direnv and nix-direnv by default for project-local dev
shells. Direnv runs in silent mode by default (`programs.direnv.silent = true`)
so entering a flake-backed project does not print the full environment diff such
as `direnv: export +AR +CC ... ~PATH` on every shell activation.
