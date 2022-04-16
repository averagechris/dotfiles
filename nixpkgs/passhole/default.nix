{ config, pkgs, ... }:

let
  utils = import ../utils pkgs;
  swayPrefix = config.wayland.windowManager.sway.config.modifier;
  passhole = pkgs.callPackage ./passhole.nix { };
in
{
  config.home.packages = with pkgs; [
    bemenu
    passhole
  ];

  config.xdg.configFile."passhole.ini".text = utils.mkINI {
    chris_shared = {
      default = true;
      database = "~/MEGAsync/keepass/chris_shared.kdbx";
      cache = "~/.cache/keepass_chris_shared_cache";
      cache-timeout = 2 * 60 * 60; # 2 hours
    };
  };

  config.wayland.windowManager.sway.config.keybindings = {

    # adds a bemenu fuzzy finder, the password choice is typed out
    # via a virtual keyboard
    "${swayPrefix}+p" = with pkgs; ''
      exec ${wlrctl}/bin/wlrctl keyboard type \
        "$(${passhole}/bin/ph show --field password \
          "$(${passhole}/bin/ph grep -i . \
            | ${bemenu}/bin/bemenu --center --margin 10 --list 10)")"
    '';
    "${swayPrefix}+Shift+p" = with pkgs; ''
      exec ${wlrctl}/bin/wlrctl keyboard type \
        "$(${passhole}/bin/ph show --field username \
          "$(${passhole}/bin/ph grep -i . \
            | ${bemenu}/bin/bemenu --center --margin 10 --list 10)")"
    '';
  };

}
