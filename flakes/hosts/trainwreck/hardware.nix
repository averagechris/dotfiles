# Hardware configuration for trainwreck (Hetzner Cloud ARM VPS)
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # Hetzner Cloud VPS uses virtio
  boot.initrd.availableKernelModules = ["virtio_pci" "virtio_scsi" "virtio_blk" "virtio_net" "xhci_pci" "sd_mod" "sr_mod"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = [];
  boot.extraModulePackages = [];

  # Hetzner networking - use DHCP
  networking.useDHCP = lib.mkDefault true;

  # ARM platform
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
