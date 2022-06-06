{
  config,
  pkgs,
  lib,
  ...
}: {
  # puts systemd init logs on tty1
  # so that tuigreet and systemd logs don't clobber each other
  boot.kernelParams = [
    "console=tty1"
  ];

  services.greetd = {
    vt = 2; # on tty 2 cause systemd logs are on tty 1
    enable = true;
    settings = {
      default_session = {
        command = "${lib.makeBinPath [pkgs.greetd.tuigreet]}/tuigreet --time --cmd sway";
        user = "greeter";
      };
    };
  };
}
