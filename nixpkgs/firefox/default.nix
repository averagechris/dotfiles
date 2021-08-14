{ pkgs, ... }:
let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
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
      settings = if isLinux then {
        # https://wiki.archlinux.org/title/HiDPI#Firefox
        "layout.css.devPixelsPerPx" = "2.0";
      } else {} // {

        # allows firefox to see userChrome.css etc
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

        "browser.startup.homepage" = "https://duckduckgo.com";
        "browser.search.region" = "US";
        "browser.search.isUS" = true;
        "browser.bookmarks.showMobileBookmarks" = true;
      };

      userChrome = builtins.readFile ./userChrome.css;
      userContent = ''
        /* Hide scrollbar */
        *{scrollbar-width: none !important}
      '';

    };
  };
}
