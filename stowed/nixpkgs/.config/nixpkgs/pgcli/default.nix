{ pkgs, lib, ... }:

let

  mkINI = lib.generators.toINI {
    mkKeyValue = key: value:
      let
        v = if lib.isBool value then
            (if value then "True" else "False")
          else
            toString value;
      in "${key} = ${v}";
  };

  pgcliConfig = {
      main = {
        smart_completion = true;
        wider_completion_menu = true;
        multi_line = true;
        destructive_warning = true;
        keyword_casing = "auto";
        show_bottom_toolbar = true;
        vi = true;  # keybindings
        prompt = "\u@\h:\d> ";
        keyring = false;  # for storing credentials
        less_chatty = true;
        enable_pager = true;

        # table_format = "ascii";
        table_format = "psql";
      };
      "named queries" = {};
      "alias dsn" = {};
    };

in {

  home.packages = with pkgs; [
    pgcli
  ];

  xdg.configFile."pgcli/config".text = ''
    # Generated by home-manager from nixpkgs.pgcli in ~/dotfiles
    # For a list of options see: https://www.pgcli.com/config

  '' + mkINI pgcliConfig;
}
