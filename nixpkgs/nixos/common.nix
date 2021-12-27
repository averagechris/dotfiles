{ config, pkgs, lib, ... }:

{
  nix = {
    package = pkgs.nixFlakes;
    binaryCaches = [ "https://cache.nixos.org/" ];
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  nixpkgs.config.allowUnfree = true;

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
    font = "${pkgs.terminus_font}/share/consolefonts/ter-u32n.psf.gz";
    keyMap = "us";
  };

  environment.systemPackages = with pkgs; [
    git
    nix-index
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
