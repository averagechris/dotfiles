# Hardware configuration for ThinkPad T14s Gen 5 AMD
#
# NOTE: After running nixos-generate-config on the actual hardware,
# merge any additional detected settings (like specific kernel modules)
# into this file.
{
  config,
  lib,
  pkgs,
  modulesPath,
  inputs,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    inputs.disko.nixosModules.disko
    ./disk-config.nix
  ];

  # Kernel modules for ThinkPad T14s Gen 5 AMD
  boot.initrd.availableKernelModules = ["nvme" "xhci_pci" "thunderbolt" "usb_storage" "sd_mod"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-amd"];
  boot.extraModulePackages = [];

  # Hibernation uses a swapfile inside the encrypted ext4 root filesystem. This
  # preserves at-rest encryption without a second LUKS prompt and avoids the
  # random-encrypted disko swap partition, whose key changes every boot and is
  # therefore not resume-capable.
  boot.resumeDevice = "/dev/disk/by-uuid/e817895a-ef3f-4289-8c9e-7e4e49703b13";
  boot.kernelParams = ["resume_offset=13852672"];
  swapDevices = lib.mkForce [
    {
      device = "/swapfile";
      size = 40960;
    }
  ];
  zramSwap.enable = lib.mkForce false;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
