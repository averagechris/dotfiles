{
  config,
  pkgs,
  lib,
  ...
}: {
  networking.networkmanager.enable = true;

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  networking.useDHCP = false;

  # https://github.com/tailscale/tailscale/issues/4432
  networking.firewall.checkReversePath = "loose";
}
