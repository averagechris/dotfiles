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

  config.wayland.windowManager.sway.config.keybindings = with pkgs; let
    bemenu_choose_passhole_entry = writeShellApplication {
      name = "bemenu_choose_passhole_entry";
      runtimeInputs = [ bemenu coreutils passhole ];
      text = "ph grep -i . | bemenu --ignorecase --center --margin 10 --list 10";
    };
    wlrctl_type_passhole_field_value = writeShellApplication {
      name = "wlrctl_type_passhole_field_value";
      runtimeInputs = [ bemenu_choose_passhole_entry wlrctl ];
      text = ''
        wlrctl keyboard type "$(ph show --field "$2" "$1")"
      '';
    };
    bemenu_choose_passhole_field = writeShellApplication {
      name = "bemenu_choose_passhole_field";
      runtimeInputs = [ bemenu coreutils passhole gnused ];
      # ph show needs the color codes and stuff stripped from it's output
      text = ''
        ph show "$1" \
          | sed 's/\x1B\[[0-9;]\{1,\}[A-Za-z]//g' \
          | cut -d : -f 1 \
          | bemenu --ignorecase --center --margin 10 --list 10
      '';
    };
  in
  {
    # adds a bemenu fuzzy finder, the password choice is typed out
    # via a virtual keyboard
    "${swayPrefix}+p" = let name = "wlrctl_type_passhole_password"; in
      "exec ${writeShellApplication {
      inherit name;
      runtimeInputs = [bemenu_choose_passhole_entry wlrctl_type_passhole_field_value];
      text = ''wlrctl_type_passhole_field_value "$(bemenu_choose_passhole_entry)" password'';
    }}/bin/${name}";

    "${swayPrefix}+Shift+p" = let name = "wlrctl_type_passhole_password"; in
      "exec ${writeShellApplication {
      inherit name;
      runtimeInputs = [bemenu_choose_passhole_entry wlrctl_type_passhole_field_value];
      text = ''wlrctl_type_passhole_field_value "$(bemenu_choose_passhole_entry)" username'';
    }}/bin/${name}";

    "${swayPrefix}+Ctrl+p" = let name = "wlrctl_type_passhole_arbitrary_field"; in
      "exec ${writeShellApplication {
      inherit name;
      runtimeInputs = [bemenu_choose_passhole_entry bemenu_choose_passhole_field wlrctl_type_passhole_field_value];
      text = ''
        ENTRY="$(bemenu_choose_passhole_entry)"
        FIELD="$(bemenu_choose_passhole_field "$ENTRY")"
        wlrctl_type_passhole_field_value "$ENTRY" "$FIELD"
      '';
    }}/bin/${name}";

  };

}
