{...}: {
  networking.networkmanager.enable = true;
  systemd.network.wait-online.enable = false; # we don't use this if we're using network manager
  systemd.services.NetworkManager-wait-online.enable = false;
  # boot.initrd.systemd.network.wait-online.enable = false;

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  networking.useDHCP = false;
}
