{ config, pkgs, lib, inputs, ... }:

{
  nix = {
    package = pkgs.nixFlakes;
    binaryCaches = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org"
      "https://nixpkgs-wayland.cachix.org"
    ];
    binaryCachePublicKeys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
    ];
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    (import inputs.emacs-overlay)
    (import inputs.wayland-overlay)
  ];

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

  # decrypt the root volume
  boot.initrd.luks.devices.root.preLVM = true;
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
