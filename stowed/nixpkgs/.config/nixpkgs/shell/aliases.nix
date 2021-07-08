let
  isLinux = (import <nixpkgs> {}).stdenv.hostPlatform.isLinux;
in {
  # warning, verbose
  cp = "cp -iv";

  # warning, verbose
  mv = "mv -iv";

  # make path, verbose
  mkdir = "mkdir -pv";

  # replecate pbcopy and pbpaste from macos everywhere 😎👍
  pbcopy = if isLinux then
      "xclip -i -selection clipboard"
    else
      "pbcopy";

  pbpaste = if isLinux then
      "xclip -o -selection clipboard"
    else
      "pbpaste";
}
