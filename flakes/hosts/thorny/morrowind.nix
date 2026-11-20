{pkgs, ...}: let
  morrowindSetup = pkgs.writeShellApplication {
    name = "morrowind-setup";
    runtimeInputs = [pkgs.python3 pkgs._7zz pkgs.unrar pkgs.openmw];
    text = ''
      exec python3 ${./morrowind-setup.py} "$@"
    '';
  };

  profileLauncher = profile: name:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [pkgs.openmw morrowindSetup];
      text = ''
        base_config_home="''${XDG_CONFIG_HOME:-$HOME/.config}"
        base_data_home="''${XDG_DATA_HOME:-$HOME/.local/share}"
        profile_config_home="$base_config_home/morrowind/${profile}"
        profile_data_home="$base_data_home/morrowind/${profile}"
        config_file="$profile_config_home/openmw/openmw.cfg"

        if [[ ! -f "$config_file" ]]; then
          morrowind-setup --profile ${profile}
        fi

        export XDG_CONFIG_HOME="$profile_config_home"
        export XDG_DATA_HOME="$profile_data_home"
        exec openmw-launcher "$@"
      '';
    };

  rebirthLauncher = profileLauncher "rebirth" "morrowind-rebirth";
  trLauncher = profileLauncher "tr" "morrowind-tr";
  rebirthDesktop = pkgs.makeDesktopItem {
    name = "morrowind-rebirth";
    desktopName = "Morrowind Rebirth";
    comment = "Launch Morrowind Rebirth in its isolated OpenMW profile";
    exec = "${rebirthLauncher}/bin/morrowind-rebirth";
    terminal = true;
    categories = ["Game"];
  };
  trDesktop = pkgs.makeDesktopItem {
    name = "morrowind-tamriel-rebuilt";
    desktopName = "Morrowind Tamriel Rebuilt";
    comment = "Launch Tamriel Rebuilt in its isolated OpenMW profile";
    exec = "${trLauncher}/bin/morrowind-tr";
    terminal = true;
    categories = ["Game"];
  };
in {
  programs.steam.enable = true;
  hardware.graphics.enable32Bit = true;

  home-manager.users.chris.home.packages = [
    pkgs.openmw
    morrowindSetup
    rebirthLauncher
    trLauncher
    rebirthDesktop
    trDesktop
    (pkgs.writeShellApplication {
      name = "morrowind";
      runtimeInputs = [rebirthLauncher];
      text = ''exec morrowind-rebirth "$@"'';
    })
  ];
}
