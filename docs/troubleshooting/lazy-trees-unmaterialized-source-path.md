# Activation fails on an unmaterialized `…-source/` path (lazy-trees)

With Determinate Nix and `lazy-trees = true`, a Home Manager or system
activation step can fail with:

```text
python3: can't open file '/nix/store/<hash>-source/flakes/hm-modules/modules/<module>/<script>.py': No such file or directory
```

## Cause

A module referenced a repository file by stringifying the path instead of
interpolating it:

```nix
script = ./merge-context.py;
# later
''${lib.escapeShellArg script}''   # toString drops the store-path context
```

`toString` (which `lib.escapeShellArg` uses) yields the virtual flake source
path without registering the file as a store dependency. Under lazy-trees that
source tree is never copied to the store, so the path does not exist at runtime.
Without lazy-trees the whole flake source happened to be in the store, which is
why this went unnoticed.

## Fix

Interpolate the path so Nix copies the file into its own store path and keeps
the string context:

```nix
script = "${./merge-context.py}";
```

Then `escapeShellArg` or direct interpolation both work. Every other script in
`flakes/hm-modules/modules/linear-cli/hygiene-automation.nix` already used
`${./file.py}` directly; only `default.nix`'s `mergeContextScript` had the bare
path.

## Finding other instances

```bash
rg -n 'escapeShellArg [a-zA-Z]+\b' flakes --glob '*.nix'
rg -n '= \./[^;]*\.(py|sh|js);' flakes --glob '*.nix'
```

Any `let` binding of a bare `./file` that is later passed through `toString`,
`escapeShellArg`, or string concatenation with `+` has the same problem. Bindings
used only inside `''${...}'' ` interpolation are fine.
