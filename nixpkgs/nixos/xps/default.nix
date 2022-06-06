{pkgs, ...}: {
  imports = [
    ./hardware-configuration.nix
  ];

  boot.initrd.luks.devices.root.device = "/dev/nvme0n1p2";
  networking.hostName = "xps-nixos";

  networking.wireless.interfaces = ["wlp0s20f3"];
  networking.interfaces.wlp6s0.useDHCP = false;

  # these opengl is needed for sway to work right on intel graphics
  hardware.opengl.enable = true;
  hardware.opengl.driSupport = true;

  system.stateVersion = "21.05";
  home-manager.users.chris = {pkgs, ...}: {
    home.stateVersion = "21.05";
  };

  boot.kernelModules = [
    "ipt_dnat"
    "ipt_mark"
    "iptable_filter"
    "iptable_nat"
    "sch_cake"
    "xt_nat"
  ];
}
