{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  nixpkgs.overlays = [
    (import inputs.emacs-overlay)
    (import inputs.wayland-overlay)
  ];

  time.timeZone = "America/Chicago";

  hardware.opengl = {
    enable = true;
    extraPackages = with pkgs; [amdvlk rocm-opencl-icd];
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
  console = {
    font = "${pkgs.terminus_font}/share/consolefonts/ter-u32n.psf.gz";
    keyMap = "us";
  };

  # decrypt the root volume
  boot.initrd.luks.devices.root.preLVM = true;
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
