{pkgs, ...}: let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in {
  programs.firefox = {
    enable = true;

    package = pkgs.firefox.override {
      cfg = {
        enableGnomeExtensions = isLinux;
      };
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
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

            "browser.startup.homepage" = "https://duckduckgo.com";
            "browser.search.region" = "US";
            "browser.search.isUS" = true;
            "browser.bookmarks.showMobileBookmarks" = true;
            "browser.toolbars.bookmarks.visibility" = "never";
          };

      userChrome = builtins.readFile ./userChrome.css;
      userContent = ''
        /* Hide scrollbar */
        *{scrollbar-width: none !important}
      '';
    };
  };
}
