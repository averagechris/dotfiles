{ pkgs, ... }:

{
  programs.firefox = {
    enable = true;

    profiles.me = {
      name = "me";
      settings = {
        "browser.startup.homepage" = "https://duckduckgo.com";
        "browser.search.region" = "US";
        "browser.search.isUS" = true;
        "browser.bookmarks.showMobileBookmarks" = true;

        # allows firefox to see userChrome.css etc
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

        # https://wiki.archlinux.org/title/HiDPI#Firefox
        "layout.css.devPixelsPerPx" = "2.0";
      };
      userChrome = builtins.readFile ./userChrome.css;
      userContent = ''
        /* Hide scrollbar */
        *{scrollbar-width: none !important}
      '';

    };
  };
}
