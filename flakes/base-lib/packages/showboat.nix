{
  buildGoModule,
  lib,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "showboat";
  version = "0.6.1";

  src = fetchFromGitHub {
    owner = "simonw";
    repo = pname;
    rev = "d531261b8faf0c388b02c7891d50f1f47c3e2b52";
    hash = "sha256-yYK6j6j7OgLABHLOSKlzNnm2AWzM2Ig76RJypBsBnkI=";
  };

  vendorHash = "sha256-mGKxBRU5TPgdmiSx0DHEd0Ys8gsVD/YdBfbDdSVpC3U=";

  ldflags = ["-X main.version=${version}"];

  subPackages = ["."];

  doCheck = false;

  meta = with lib; {
    description = "CLI for creating executable documents that capture agent work";
    homepage = "https://github.com/simonw/showboat";
    license = licenses.asl20;
    mainProgram = "showboat";
    platforms = platforms.unix;
  };
}
