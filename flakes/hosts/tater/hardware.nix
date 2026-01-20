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

  # Enable hibernation (resume from swap)
  # The swap partition is randomly encrypted, so hibernation requires
  # a persistent swap. If you need hibernation, change disk-config.nix
  # to use a LUKS-encrypted swap instead of randomEncryption.
  # boot.resumeDevice = "/dev/disk/by-label/swap";

  # Swap is handled by disko (see disk-config.nix)
  swapDevices = [];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
