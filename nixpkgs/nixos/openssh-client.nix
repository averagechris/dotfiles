{
  lib,
  pkgs,
  config,
  dotfiles_lib,
  ...
}: let
  cfg = config.dotfiles.opensshClient.safeConfig;
  inherit (lib) mkIf mkOption types mkDefault mdDoc optional;
in {
  options.dotfiles.opensshClient.safeConfig = {
    enable = dotfiles_lib.options.mkDefaultEnabledOption "Install a safe system ssh client config that only includes files from /etc (avoids /nix/store vendor drop-ins with OpenSSH strict permission checks).";

    copySystemdProxyDropin = mkOption {
      type = types.bool;
      default = false;
      description = mdDoc "If true, copy systemd's ssh proxy drop-in into /etc as a real file so OpenSSH accepts it.";
    };
  };

  config = mkIf cfg.enable {
    # Provide a minimal, safe ssh_config that includes only /etc drop-ins.
    # mkDefault so hosts can override if they need custom settings.
    environment.etc."ssh/ssh_config".text = mkDefault ''
      Include /etc/ssh/ssh_config.d/*.conf

      Host *
        SendEnv LANG LC_*
        HashKnownHosts yes
    '';

    # Ensure the drop-in directory exists as a real directory under /etc.
    systemd.tmpfiles.rules =
      [
        "d /etc/ssh/ssh_config.d 0755 root root - -"
      ]
      ++ lib.optionals cfg.copySystemdProxyDropin [
        "C! /etc/ssh/ssh_config.d/20-systemd-ssh-proxy.conf 0644 root root - ${pkgs.systemd}/lib/systemd/ssh_config.d/20-systemd-ssh-proxy.conf"
      ];
  };
}
