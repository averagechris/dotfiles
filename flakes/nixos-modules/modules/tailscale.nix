{
  config,
  pkgs,
  ...
}: {
  environment.systemPackages = [pkgs.tailscale];
  services.tailscale.enable = true;

  networking.firewall = {
    enable = true;
    trustedInterfaces = ["tailscale0"];
    allowedUDPPorts = [config.services.tailscale.port];
    allowedTCPPorts = [22];
    # https://github.com/tailscale/tailscale/issues/4432
    checkReversePath = "loose";
  };
  networking.networkmanager.unmanaged = ["tailscale0"];

  networking.nameservers = [
    "100.100.100.100"
    "1.1.1.1"
    "9.9.9.9"
  ];
}
