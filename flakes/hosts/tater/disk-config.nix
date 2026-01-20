# Declarative disk configuration for ThinkPad T14s Gen 5 AMD
# Uses disko to partition, encrypt, and format the NVMe drive
#
# Layout:
#   /dev/nvme0n1p1 - 512MB EFI System Partition (FAT32) -> /boot
#   /dev/nvme0n1p2 - LUKS encrypted container
#     └── /dev/mapper/cryptroot - ext4 -> /
#   /dev/nvme0n1p3 - 16GB swap (for hibernation)
#
# To apply manually from installer:
#   sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- --mode disko ./flakes/hosts/tater/disk-config.nix
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["umask=0077"];
              };
            };
            luks = {
              size = "-16G"; # All space except last 16GB
              content = {
                type = "luks";
                name = "cryptroot";
                settings = {
                  allowDiscards = true; # SSD TRIM support
                };
                # Password will be prompted interactively during disko run
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                  mountOptions = ["noatime"];
                };
              };
            };
            swap = {
              size = "100%"; # Remaining 16GB
              content = {
                type = "swap";
                randomEncryption = true; # Encrypt swap with random key each boot
              };
            };
          };
        };
      };
    };
  };
}
