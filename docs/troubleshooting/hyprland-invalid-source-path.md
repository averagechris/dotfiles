# Hyprland invalid source path during flake evaluation

`nix flake check --no-build` can fail on Hyprland hosts with an error like:

```text
error: path '/nix/store/...-source' is not valid
```

The trace points at Hyprland's upstream package reading `VERSION` from its
fileset-filtered `finalAttrs.src` while constructing `GIT_TAG`. In no-build
evaluation contexts that filtered source may not be realised yet.

Tater and thorny work around this by overriding only `env.GIT_TAG` from the
Hyprland flake source's `VERSION` file, while leaving the pinned Hyprland package
and plugin ABI intact.
