{
  pkgs,
  lib,
  overlays,
  ...
}: {
  nixpkgs.overlays = lib.attrValues overlays;

  time.timeZone = lib.mkDefault "America/Los_Angeles";

  # Keep the system clock synchronized from internet NTP sources. This is
  # especially useful on laptops after battery drain, suspend, or RTC drift.
  services.timesyncd = {
    enable = true;
    servers = [
      "time.cloudflare.com"
      "time.google.com"
      "pool.ntp.org"
    ];
    fallbackServers = [
      "0.nixos.pool.ntp.org"
      "1.nixos.pool.ntp.org"
      "2.nixos.pool.ntp.org"
      "3.nixos.pool.ntp.org"
    ];
  };

  hardware.graphics = {
    enable = true;
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

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
