# Home Manager package path collisions

Home Manager builds the user profile with `pkgs.buildEnv`, so two packages in
`home.packages` cannot provide the same path unless the collision is explicitly
removed before the profile is assembled.

Example failure:

```text
pkgs.buildEnv error: two given paths contain a conflicting subpath:
  `...-openclaw-.../bin/idle' and
  `...-python3-.../bin/idle'
```

On `tater`, Openclaw's bundled Python environment exposes `bin/idle*` and other
Python launchers while the normal Python package also exposes those paths. The
host configuration sets `programs.openclaw.excludeTools = ["python3"]`, preserving
Openclaw itself while relying on the Python package that is already in the user
profile.

For similar collisions, prefer fixing the specific package output that adds the
unneeded path rather than disabling unrelated packages from the user profile.
