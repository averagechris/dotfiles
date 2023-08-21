{...}: {
  # puts systemd init logs on tty1
  # so that tuigreet and systemd logs don't clobber each other
  boot.kernelParams = [
    "console=tty1"
  ];
  programs.regreet = {
    enable = true;
    settings = {
      background.path = ../../hm_modules/gui/wallpapers/1.jpg;
      background.fit = "Fill";
      GTK.application_prefer_dark_theme = true;
      commands.reboot = ["systemctl" "reboot"];
      commands.poweroff = ["systemctl" "poweroff"];
    };
  };
  services.greetd = {
    vt = 2; # on tty 2 cause systemd logs are on tty 1
    enable = true;
  };
}
