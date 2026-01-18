{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.nixos-modules.nixosModules.common
    inputs.nixos-modules.nixosModules.desktopCommon
    inputs.nixos-modules.nixosModules.docker
    inputs.nixos-modules.nixosModules.graphical
    inputs.nixos-modules.nixosModules.networking
    inputs.nixos-modules.nixosModules.sound
    inputs.nixos-modules.nixosModules.tailscale
    inputs.nixos-modules.nixosModules.virtualization
    inputs.nixos-modules.nixosModules.users.chris
    inputs.nixos-modules.nixosModules.cosmicDesktop
    ./hardware.nix
    inputs.agenix.nixosModules.default
    inputs.nixos-hardware.nixosModules.system76
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate
    inputs.nixos-hardware.nixosModules.common-pc-ssd
  ];

  dotfiles.cosmic.enable = true;
  dotfiles.cosmic.system76.enable = true;

  boot.initrd.luks.devices = {
    root.device = "/dev/nvme1n1p2";
    root.preLVM = true;
  };

  # a regression around 25.11 broke this, i should be able to remove in the near future
  boot.kernel.sysctl."kernel.unprivileged_userns_clone" = 0;

  networking.hostName = "trap";

  hardware.graphics.enable = true;
  hardware.enableRedistributableFirmware = true;
  system.stateVersion = "24.11";
  home-manager.users.chris = {...}: {
    home.stateVersion = "24.11";
    imports = [
      inputs.hm-modules.homeManagerModules.default
    ];
    dotfiles.cosmic-workstation.enable = true;
    dotfiles.cosmic-workstation.ghostty.enable = true;
    programs.opencode.enable = true;
    programs.meganz.enable = true;
  };

  users.users.chris.extraGroups = ["docker"];
}
