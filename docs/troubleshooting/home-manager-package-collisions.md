# Home Manager package path collisions

Home Manager builds the user profile with `pkgs.buildEnv`, so two packages in
`home.packages` cannot provide the same path unless the collision is explicitly
removed before the profile is assembled.

Example failure pattern:

```text
pkgs.buildEnv error: two given paths contain a conflicting subpath:
  `...-package-a.../bin/tool' and
  `...-package-b.../bin/tool'
```

A historical example was a bundled Python environment exposing `bin/idle*` while
the normal Python package exposed the same paths:

```text
pkgs.buildEnv error: two given paths contain a conflicting subpath:
  `...-bundled-python-app.../bin/idle' and
  `...-python3-.../bin/idle'
```

For similar collisions, prefer fixing the specific package output that adds the
unneeded path rather than disabling unrelated packages from the user profile.
