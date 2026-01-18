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
    inputs.nixos-modules.nixosModules.users.chris
    inputs.nixos-modules.nixosModules.cosmicDesktop
    ./hardware.nix
    inputs.agenix.nixosModules.default
    inputs.nixos-hardware.nixosModules.system76
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-gpu-amd
    inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate
    inputs.nixos-hardware.nixosModules.common-pc-ssd
  ];

  dotfiles.cosmic.enable = true;
  dotfiles.cosmic.system76.enable = true;

  boot.initrd.luks.devices.root.device = "/dev/sda2";
  networking.hostName = "thorny";

  networking.wireless.interfaces = ["wlp6s0"];

  environment.systemPackages = with pkgs; [
    mesa
  ];
  hardware.graphics.enable = true;
  hardware.enableRedistributableFirmware = true;

  programs.steam.enable = true;
  hardware.xone.enable = true;

  system.stateVersion = "24.11";
  home-manager.users.chris = {...}: {
    home.stateVersion = "24.11";
    imports = [
      inputs.hm-modules.homeManagerModules.default
    ];
    dotfiles.cosmic-workstation.enable = true;
    programs.meganz.enable = true;

    dotfiles.helix-terminal-tools = {
      enable = true;
      yazi = {
        enable = true;
        pickerWidth = 30;
        pickerSide = "left";
        helixKeybinding = "space.t.f"; # Toggle file picker
      };
      claude = {
        enable = true;
      };
    };
    programs.opencode.enable = true;
    home.packages = [pkgs.claude-code];
  };
}
