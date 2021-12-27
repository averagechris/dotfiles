{ config, pkgs, lib, ... }:

let
  scrnXps13 = {
    criteria = "eDP-1";
    status = "enable";
    scale = 2.0;
  };

  scrnDell43 = {
    criteria = "Dell Inc. DELL U4320Q 1LTJW13";
    status = "enable";
    mode = "3840x2160@59.997Hz";
    position = "1440,0";
  };

  scrnDell27 = {
    criteria = "Dell Inc. DELL U2713HM 7JNY544BAB6S";
    status = "enable";
    mode = "2560x1440@59.951Hz";
    position = "0,0";
    transform = "270";
  };

in
{
  config.services.kanshi = {
    enable = true;
    profiles = {
      laptop-unplugged = {
        outputs = [
          scrnXps13
        ];
      };
      laptop-home-office = {
        exec = [
          "${pkgs.sway}/bin/swaymsg workspace 1, move workspace to ${scrnXps13.criteria}"
        ];
        outputs = [
          (scrnXps13 // { status = "disable"; })
          scrnDell43
          scrnDell27
        ];
      };
      home-office = {
        outputs = [
          # TODO: is full res not supported via HDMI for some reason?
          # Dell27's max res available is only 1080 wide, so we have to adjust the position
          # of Dell43 to match
          (scrnDell43 // { position = "1080,0"; })
          (scrnDell27 // { mode = "1920x1080@60.000Hz"; })
        ];
      };
    };
  };
}
