{
  config,
  lib,
  pkgs,
  dotfiles_lib,
  ...
}: let
  cfg = config.dotfiles.shell.pipx;
in {
  options.dotfiles.shell.pipx = {
    enable = lib.mkEnableOption "adds pipx to home packages and by default adds pipx's install path to ZSH PATH";
    zsh.enable = dotfiles_lib.options.mkDefaultEnabledOption "adds pipx's install path to zsh PATH";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [pkgs.pipx];
    programs.zsh = lib.mkIf cfg.zsh.enable {
      initContent = ''
        export PATH=$HOME/.local/bin:$PATH
      '';
    };
  };
}
