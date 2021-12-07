{ config, pkgs, lib, ... }:

{
  nix.binaryCaches = [ "https://cache.nixos.org/" ];

  time.timeZone = "America/Chicago";

  hardware.opengl = {
    enable = true;
    extraPackages = with pkgs; [ amdvlk rocm-opencl-icd ];
    driSupport = true;
  };

  system.autoUpgrade = {
    enable = true;
    allowReboot = true;
  };

  services.openssh.enable = true;

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Select internationalization properties.
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  environment.systemPackages = with pkgs; [
    git
    nix-prefetch-scripts
    neovim
    which
  ];

  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  # decrypt the root volume
  boot.initrd.luks.devices.root.preLVM = true;
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
