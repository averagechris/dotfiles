{...}: {
  # #############
  # Enable sound.
  # #############
  #
  # these are disabled in favor of PipeWire
  # https://nixos.wiki/wiki/PipeWire
  # #######################################
  sound.enable = true;
  hardware.pulseaudio.enable = true;
  # #######################################

  security.rtkit.enable = true; # rtkit is optional but recommended
  services.pipewire = {
    enable = false;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # unstable uses wireplumber now: https://nixos.wiki/wiki/PipeWire
  # services.pipewire.wireplumber.enable = true;
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
  # hardware.bluetooth.hsphfpd.enable = false; # Using Wireplumber conflicts with hsphfpd, as it provides the same functionality.
  hardware.bluetooth.hsphfpd.enable = true;
  services.blueman.enable = true;
  systemd.user.services.telephony_client.enable = false;
  hardware.bluetooth.powerOnBoot = true;
}
