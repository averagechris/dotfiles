{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
  nested = prefix: bindings: with lib.attrsets; mapAttrs' (k: v: nameValuePair "${prefix}>${k}" v) bindings;
  prefixed = nested "shift+space";
  tabp = nested "shift+space>t";
  windowp = nested "shift+space>w";
in {
  programs.kitty = {
    keybindings =
      {
        "ctrl+shift+c" = "copy_to_clipboard";
        "ctrl+shift+v" = "paste_from_clipboard";
      }
      // (
        if isDarwin
        then {
          "cmd+plus" = "change_font_size current +2.0";
          "cmd+minus" = "change_font_size current -2.0";
          "cmd+0" = "change_font_size current 0";
        }
        else if isLinux
        then {
          "ctrl+shift+plus" = "change_font_size current +2.0";
          "ctrl+shift+minus" = "change_font_size current -2.0";
          "ctrl+shift+0" = "change_font_size current 0";
        }
        else {}
      )
      // (prefixed {
        c = "copy_to_clipboard";
        l = "load_config_file";
        v = "paste_from_clipboard";
        "f1" = "launch --type=overlay --stdin-source=@screen_scrollback hx";
        "m>m" = "create_marker";
        "m>shift+m" = "remove_marker";
      })
      // (windowp {
        d = "close_window_with_confirmation";
        f = "toggle_layout stack";
        r = "start_resizing_window";
        n = "neighboring_window bottom";
        e = "neighboring_window top";
        m = "neighboring_window left";
        i = "neighboring_window right";
        s = "launch --location=after --cwd=current";
        v = "launch --location=vsplit --cwd=current";
        "shift+d" = "detach_window";
        "shift+n" = "new_window_with_cwd";
        "shift+r" = "set_window_title";
        "shift+s" = "swap_with_window";
      })
      // (tabp {
        i = "next_tab";
        m = "prev_tab";
        r = "set_tab_title";
        n = "combine : new_tab : goto_tab -1";
        t = "select_tab";
        d = "close_tab";
        "shift+d" = "detach_tab";
        "1" = "goto_tab 1";
        "2" = "goto_tab 2";
        "3" = "goto_tab 3";
        "4" = "goto_tab 4";
        "5" = "goto_tab 5";
        "6" = "goto_tab 6";
        "7" = "goto_tab 7";
        "8" = "goto_tab 8";
        "9" = "goto_tab 9";
      });
    settings = {
      clear_all_shortcuts = true;
      allow_remote_control = "socket-only";
      listen_on = "unix:/tmp/main-kitty-socket";
      macos_option_as_alt = true;
      macos_quit_when_last_window_closed = true;
      scrollback_pager =
        if config.programs.helix.enable
        then "hx"
        else "scrollback_pager less --chop-long-lines --RAW-CONTROL-CHARS +INPUT_LINE_NUMBER";
      paste_actions = "quote-urls-at-prompt,confirm";
      strip_trailing_spaces = "smart";
      tab_bar_style = "powerline";
    };
    theme = "Rosé Pine Moon";
    extraConfig = ''
      include extra.kitty.conf
    '';
  };
}
