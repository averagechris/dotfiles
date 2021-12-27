{ pkgs }:
let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
in
{
  # warning, verbose
  cp = "cp -iv";

  # warning, verbose
  mv = "mv -iv";

  # make path, verbose
  mkdir = "mkdir -pv";

  # replecate pbcopy and pbpaste from macos everywhere 😎👍
  pbcopy =
    if isLinux then
      "wl-copy"
    else
      "pbcopy";

  pbpaste =
    if isLinux then
      "wl-paste"
    else
      "pbpaste";
}
