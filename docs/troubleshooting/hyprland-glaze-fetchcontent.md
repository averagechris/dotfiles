# Hyprland build fails fetching glaze with FetchContent

The pinned Hyprland CI job can fail during configure with an error like:

```text
-- glaze dependency not found, retrieving v7.0.0 with FetchContent
CMake Error ... could not find git for clone of glaze-populate
hyprpm/CMakeLists.txt:26 (FetchContent_MakeAvailable)
```

## Why this happens

Tater and thorny pin the `hyprland` flake input so the compositor and plugin ABI
stay consistent. The pinned source's `hyprpm/CMakeLists.txt` asks for
`find_package(glaze 7.0.0 QUIET)`, and glaze installs its package version file
with `SameMajorVersion` compatibility. When nixpkgs ships glaze 8.x, the version
check rejects it, configure falls back to FetchContent, and FetchContent tries a
git clone that cannot run inside the Nix sandbox.

Only hyprpm consumes glaze; the compositor itself does not.

## The fix

`flakes/base-lib/packages/glaze-v7.nix` packages glaze 7.x from a fixed upstream
tag, and the base-lib overlay exposes it as `glaze-v7`. Both hosts append
`-Dglaze_DIR=<glaze-v7>/share/glaze` to the pinned Hyprland package's
`cmakeFlags`. `find_package(glaze 7.0.0 QUIET)` runs in CONFIG mode, and CONFIG
mode honors a pre-set `<PackageName>_DIR` cache entry before any prefix search,
so CMake loads `share/glaze/glazeConfig.cmake` directly, sees version 7.9.1,
passes the SameMajorVersion check, and never reaches the FetchContent fallback.

An earlier attempt added `glaze-v7` to `nativeBuildInputs` instead, relying on
nixpkgs' cmake hook to put it on `NIXPKGS_CMAKE_PREFIX_PATH` (which nixpkgs'
patched cmake searches during find_package). CI disproved that route: glaze-v7
built, entered the closure, and appeared in the derivation's
`nativeBuildInputs`, yet configure still reported the dependency missing and hit
the FetchContent clone. The exact propagation gap was never isolated, so the
build now bypasses discovery entirely with an explicit cache variable that does
not depend on environment plumbing.

Keep `glaze-v7` on a 7.x release while the pin lasts. When the Hyprland pin
moves to a revision that accepts current nixpkgs glaze, delete the package, the
overlay entry, and both host overrides.
