{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in {
  home.sessionVariables = lib.mkIf config.programs.firefox.enable {
    BROSWER = "firefox";
  };

  programs.firefox = {
    package = pkgs.firefox.override {
      cfg.enableGnomeExtensions = lib.mkDefault isLinux;
    };

    profiles.me = {
      name = "me";
      settings =
        if isLinux
        then {
          # https://wiki.archlinux.org/title/Firefox#Hardware_video_acceleration
          "media.ffmpeg.vaapi.enabled" = true;
          "media.ffvpx.enabled" = false;
          "media.rdd-vpx.enabled" = false;
          "media.navigator.mediadatadecoder_vpx_enabled" = true;
          "security.sandbox.content.level" = 0;
        }
        else
          {}
          // {
            # allows firefox to see userChrome.css etc
            # NOTE: I always still have to _manually_ toggle this one once :(
            # by going to about:config, copy-pasting this, then toggling it to true
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

            "browser.startup.homepage" = "https://duckduckgo.com";
            "browser.search.region" = "US";
            "browser.search.isUS" = true;
            "browser.bookmarks.showMobileBookmarks" = true;
            "browser.toolbars.bookmarks.visibility" = "never";
          };

      userContent = ''
        /* Hide scrollbar */
        *{scrollbar-width: none !important}
      '';
      userChrome = ''
        @namespace url(http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul);

        /* hides firefox's default tab bar */
        #tabbrowser-tabs {
            visibility: collapse !important;
        }

        /* makes the treestyle tab view look cleaner */
        #sidebar-box[sidebarcommand="treestyletab_piro_sakura_ne_jp-sidebar-action"] #sidebar-header {
            display: none;
        }
      '';
    };
  };

  # this makes it so firefox uses wayland instead of xwayland
  wayland.windowManager.sway = lib.mkIf config.wayland.windowManager.sway.enable {
    extraSessionCommands = ''
      export MOZ_ENABLE_WAYLAND=1
      export MOZ_DBUS_REMOTE=1
    '';
  };
}
