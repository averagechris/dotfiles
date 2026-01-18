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
    inputs.nixos-hardware.nixosModules.dell-xps-13-9310
    inputs.nixos-hardware.nixosModules.common-cpu-intel
    inputs.nixos-hardware.nixosModules.common-pc-ssd
  ];

  dotfiles.cosmic.enable = true;

  boot.initrd.luks.devices.root.device = "/dev/nvme0n1p2";
  networking.hostName = "cruber";

  networking.wireless.interfaces = ["wlp0s20f3"];
  networking.interfaces.wlp0s20f3.useDHCP = true;

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
    dotfiles.shell.calibre-utils.enable = true;
    dotfiles.shell.python.enable = true;
    dotfiles.shell.pipx.enable = true;
    dotfiles.shell.yazi.enable = true;
    dotfiles.wezterm.enable = true;
    programs.helix.terminal.flavor = "wezterm";
    dotfiles.helix-terminal-tools = {
      enable = true;
      yazi = {
        enable = true;
        pickerWidth = 30;
        pickerSide = "left";
        helixKeybinding = "space.t.f"; # Toggle file picker
      };
    };
    programs.opencode.enable = true;
    programs.meganz.enable = true;
  };

  users.users.chris.extraGroups = ["docker"];

  boot.kernelModules = [
    "ipt_dnat"
    "ipt_mark"
    "iptable_filter"
    "iptable_nat"
    "sch_cake"
    "xt_nat"
  ];
}
