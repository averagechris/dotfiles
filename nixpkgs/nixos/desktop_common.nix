{
  config,
  pkgs,
  lib,
  overlays,
  ...
}: {
  nixpkgs.overlays = lib.attrValues overlays;

  time.timeZone = "America/Chicago";

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [amdvlk];
  };

  system.autoUpgrade = {
    enable = true;
    allowReboot = true;
  };

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = false;
  };

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
