{ pkgs }:
with pkgs;
let
  inherit (stdenv.hostPlatform) isLinux;
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
      "${wl-clipboard}/bin/wl-copy"
    else
      "pbcopy";

  pbpaste =
    if isLinux then
      "${wl-clipboard}/bin/wl-paste"
    else
      "pbpaste";

  nixos-switch = "nixos-rebuild switch --use-remote-sudo";

  today = "date +%Y-%m-%d";
}
