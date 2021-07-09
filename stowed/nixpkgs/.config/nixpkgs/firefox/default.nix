{ pkgs, ... }:

{
  programs.firefox = {
    enable = true;

    package = pkgs.firefox.override {
      cfg = {
        enableGnomeExtensions = true;
      };
    };

    profiles.mine = {
      id = 0;
      settings = {
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
