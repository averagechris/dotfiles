{ pkgs, lib, ... }:

let
  utils = import ../utils pkgs;
  mycliConfig = {
    general = {
      smart_completion = true;
      multi_line = true;
      destructive_warning = true;
      table_format = "ascii";
      key_bindings = "vi";
      wider_completion_menu = true;
      less_chatty = true;
      keyword_casing = "auto";
      enable_pager = true;
    };
  };
in
{

  home.packages = with pkgs; [
    mycli
  ];

  home.file.".myclirc".text = ''
    # Generated by home-manager from nixpkgs.mycli in ~/dotfiles
    # For a list of options see: https://www.mycli.net/config

  '' + utils.mkINI mycliConfig;
}
