{
  config,
  pkgs,
  ...
}: {
  programs.neovim = {
    vimAlias = true;
    extraConfig = ''
    '';
  };
}
