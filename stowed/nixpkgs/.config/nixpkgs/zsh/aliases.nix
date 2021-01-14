let
  hostPlatform = (import <nixpkgs> {}).stdenv.hostPlatform;
  copycmd = isLinux:
    if isLinux then
      "xclip -i -selection clipboard"
    else
      "pbcopy";

  pastecmd = isLinux:
    if isLinux then
      "xclip -o -selection clipboard"
    else
      "pbpaste";

in {
  # warning, verbose
  cp = "cp -iv";

  # warning, verbose
  mv = "mv -iv";

  # make path, verbose
  mkdir = "mkdir -pv";

  pbcopy = copycmd (hostPlatform.isLinux);
  pbpaste = pastecmd (hostPlatform.isLinux);
}
