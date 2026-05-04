{...}: {
  # #############
  # Enable sound.
  # #############
  #
  # these are disabled in favor of PipeWire
  # https://nixos.wiki/wiki/PipeWire
  # #######################################
  # sound.enable = true;
  # hardware.pulseaudio.enable = true;
  # #######################################

  security.rtkit.enable = true; # rtkit is optional but recommended
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # unstable uses wireplumber now: https://nixos.wiki/wiki/PipeWire
  services.pipewire.wireplumber = {
    enable = true;

    # Prefer the outputs in the order humans usually expect on laptops:
    # headphones > USB speakers > monitor audio > laptop speakers. Rules are
    # ordered from lowest to highest priority so more specific later matches can
    # override generic earlier matches. Generic USB sinks rank as speakers, while
    # explicit headset/headphone labels rank higher as headphones. AudioEngine
    # sinks are matched before the generic USB rule so the HD3's misleading
    # chipset description does not stop it from being preferred over monitor and
    # laptop audio.
    # The helper CLI in the home-manager audio-output module is still the
    # explicit override for when an application keeps an old stream route.
    extraConfig."51-dotfiles-output-priorities" = {
      "monitor.bluez.properties" = {
        # Prefer high-quality Bluetooth playback. When a headset microphone is
        # selected, Bluetooth must use a headset profile with lower playback
        # quality; for listening, WirePlumber should prefer A2DP codecs.
        "bluez5.roles" = ["a2dp_sink" "a2dp_source" "bap_sink" "bap_source" "hfp_hf" "hfp_ag"];
        "bluez5.codecs" = ["ldac" "aptx_hd" "aptx" "aac" "sbc_xq" "sbc"];
        "bluez5.enable-sbc-xq" = true;
        "bluez5.enable-msbc" = true;
        "bluez5.enable-hw-volume" = true;
      };

      "monitor.alsa.rules" = [
        {
          matches = [
            {
              "media.class" = "Audio/Sink";
              "node.description" = "~.*(Built-in|Speaker).*";
            }
            {
              "media.class" = "Audio/Sink";
              "node.name" = "~alsa_output\\.pci.*analog.*";
            }
          ];
          actions.update-props = {
            "priority.session" = 1000;
            "priority.driver" = 1000;
          };
        }
        {
          matches = [
            {
              "media.class" = "Audio/Sink";
              "node.description" = "~.*(HDMI|DisplayPort|Display Port|Monitor).*";
            }
            {
              "media.class" = "Audio/Sink";
              "node.name" = "~alsa_output\\..*(hdmi|displayport).*";
            }
          ];
          actions.update-props = {
            "priority.session" = 2000;
            "priority.driver" = 2000;
          };
        }
        {
          matches = [
            {
              "media.class" = "Audio/Sink";
              "node.description" = "~.*(USB Audio).*";
            }
            {
              "media.class" = "Audio/Sink";
              "node.name" = "~alsa_output\\.usb.*";
            }
          ];
          actions.update-props = {
            "priority.session" = 3000;
            "priority.driver" = 3000;
          };
        }
        {
          matches = [
            {
              "media.class" = "Audio/Sink";
              "node.description" = "~.*AudioEngine.*";
            }
            {
              "media.class" = "Audio/Sink";
              "node.name" = "~.*Audioengine.*";
            }
          ];
          actions.update-props = {
            "priority.session" = 3500;
            "priority.driver" = 3500;
          };
        }
        {
          matches = [
            {
              "media.class" = "Audio/Sink";
              "node.description" = "~.*(Headphones|Headset|Earbuds).*";
            }
            {
              "media.class" = "Audio/Sink";
              "node.name" = "~.*(headphones|headset).*";
            }
          ];
          actions.update-props = {
            "priority.session" = 4000;
            "priority.driver" = 4000;
          };
        }
      ];

      "monitor.bluez.rules" = [
        {
          matches = [
            {
              "media.class" = "Audio/Sink";
              "node.name" = "~bluez_output.*";
            }
            {
              "media.class" = "Audio/Sink";
              "node.description" = "~.*(AirPods|AirPods Pro|Headphones|Headset|Earbuds).*";
            }
          ];
          actions.update-props = {
            "priority.session" = 4500;
            "priority.driver" = 4500;
          };
        }
      ];
    };
  };
  # environment.etc = {
  #   "wireplumber/bluetooth.lua.d/51-bluez-config.lua".text = ''
  #     bluez_monitor.properties = {
  #     	["bluez5.enable-sbc-xq"] = true,
  #     	["bluez5.enable-msbc"] = true,
  #     	["bluez5.enable-hw-volume"] = true,
  #     	["bluez5.headset-roles"] = "[ hsp_hs hsp_ag hfp_hf hfp_ag ]"
  #     }
  #   '';
  # };

  # bluetooth config is related to sound right? 😀👍
  hardware.bluetooth.enable = true;
  hardware.bluetooth.hsphfpd.enable = false; # Using Wireplumber conflicts with hsphfpd, as it provides the same functionality.
  # hardware.bluetooth.hsphfpd.enable = true;
  services.blueman.enable = true;
  systemd.user.services.telephony_client.enable = false;
  hardware.bluetooth.powerOnBoot = true;
}
