{
  fetchFromGitHub,
  lib,
  stdenv,
  cmake,
}:
# Glaze 7.x for the pinned Hyprland flake input. hyprpm's CMakeLists asks for
# find_package(glaze 7.0.0), and glaze's package config uses SameMajorVersion
# checks, so nixpkgs glaze 8.x is rejected and configure falls back to a
# FetchContent git clone that cannot run in the build sandbox. Hosts building
# the pinned Hyprland pass -Dglaze_DIR=<this package>/share/glaze in cmakeFlags
# so the version check succeeds against real headers instead.
stdenv.mkDerivation rec {
  pname = "glaze-v7";
  version = "7.9.1";

  src = fetchFromGitHub {
    owner = "stephenberry";
    repo = "glaze";
    tag = "v${version}";
    hash = "sha256-NRRq5MGF2f5PW0teYnq58ELzson+U6KHVPaY6r30KLA=";
  };

  nativeBuildInputs = [cmake];

  # Header-only INTERFACE library: there is nothing to compile or test.
  doCheck = false;

  meta = {
    description = "Glaze 7.x for consumers pinned to the glaze 7 major version";
    homepage = "https://stephenberry.github.io/glaze/";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
