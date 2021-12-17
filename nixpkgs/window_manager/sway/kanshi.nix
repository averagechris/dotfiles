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
          {
            criteria = "Dell Inc. DELL U4320Q 1LTJW13";
            mode = "3840x2160@59.997Hz";
          }
          {
            criteria = "Dell Inc. DELL U2713HM 7JNY544BAB6S";
            mode = "2560x1440@59.951Hz";
            transform = "270";
          }
        ];
      };
    };
  };
}
