{
  lib,
  config,
  pkgs,
  ...
}: {
  options.dotfiles.cosmic = {
    enable = lib.mkEnableOption "COSMIC desktop environment";
    system76.enable = lib.mkEnableOption "System76 hardware support (firmware and hardware.system76.enableAll)";
  };

  config = lib.mkIf config.dotfiles.cosmic.enable {
    services.desktopManager.cosmic.enable = lib.mkDefault true;
    services.displayManager.cosmic-greeter.enable = lib.mkDefault true;

    environment.sessionVariables.COSMIC_DATA_CONTROL_ENABLED = lib.mkDefault 1;

    services.dbus.enable = lib.mkDefault true;
    services.flatpak.enable = lib.mkDefault true;
    services.fwupd.enable = lib.mkDefault true;

    xdg.portal = lib.mkDefault {
      enable = true;
      # Prefer COSMIC, keep GTK fallback for missing interfaces
      extraPortals = [pkgs.xdg-desktop-portal-cosmic pkgs.xdg-desktop-portal-gtk];
      config.common.default = ["cosmic" "gtk"];
    };

    fonts.enableDefaultPackages = lib.mkDefault true;
    fonts.packages = lib.mkDefault (with pkgs; [
      dejavu_fonts
      font-awesome
      nerd-fonts.droid-sans-mono
      nerd-fonts.fira-code
    ]);

    environment.systemPackages = lib.mkDefault (
      with pkgs;
        [
          cosmic-ext-ctl
          cosmic-ext-tweaks
          examine
        ]
        ++ lib.optionals config.dotfiles.cosmic.system76.enable [
          system76-firmware
        ]
    );

    hardware.system76.enableAll = lib.mkIf config.dotfiles.cosmic.system76.enable (lib.mkDefault true);
  };
}
