{
  pkgs,
  config,
  ...
}: {
  programs.zsh.shellAliases = {
    # warning, verbose
    cp = "cp -iv";

    # warning, verbose
    mv = "mv -iv";

    # make path, verbose
    mkdir = "mkdir -pv";

    pbcopy = config.dotfiles.shell.commands.copy;
    pbpaste = config.dotfiles.shell.commands.paste;

    nixos-switch = "nixos-rebuild switch --use-remote-sudo";
    nixos-test = "nixos-rebuild test --use-remote-sudo";

    today = "date +%Y-%m-%d";
  };
}
