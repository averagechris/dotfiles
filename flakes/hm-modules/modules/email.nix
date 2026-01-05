{
  config,
  lib,
  pkgs,
  secrets,
  ...
}: let
  cfg = config.dotfiles.email;
in
  with lib; {
    options.dotfiles.email = {
      enable = mkEnableOption "enable email via mbsync";
      address = mkOption {
        type = types.str;
        example = "email@example.com";
        description = "The email address.";
      };
      real_name = mkOption {
        type = types.str;
        default = "Chris Cummings";
        example = "Chris Cummings";
        description = "The name associated with the email address.";
      };
      imap.host = mkOption {
        type = types.str;
        default = "imap.fastmail.com";
        example = "imap.fastmail.com";
        description = "the host url for imap for this email.";
      };
      smtp.host = mkOption {
        type = types.str;
        default = "smtp.fastmail.com";
        example = "smtp.fastmail.com";
        description = "the host url for smtp for this email.";
      };
      password_secret = mkOption {
        type = types.path;
        default = secrets.fastmail_password.path;
        example = "";
        description = "use rage to encrypt secret, pass it to this variable.";
      };
    };

    config = mkIf cfg.enable {
      programs.mu.enable = mkDefault cfg.enable;
      programs.msmtp.enable = mkDefault cfg.enable;
      programs.mbsync = {
        enable = mkDefault cfg.enable;
        extraConfig = ''
          CopyArrivalDate yes
        '';
        groups = {
          personal-inboxes = {
            "${cfg.address}" = [];
          };
        };
      };

      services.mbsync = {
        enable = mkDefault cfg.enable;
        frequency = "*:0/10";
        postExec = "${pkgs.mu}/bin/mu index";
      };

      # TODO create systemd oneshot job to run `mbsync --all`
      # and mu init
      # and mu index
      # so new systems are auto-setup
      # without having to run those commands manually
      accounts.email.accounts = {
        "${primaryAddress}" = {
          inherit (cfg) address;
          userName = cfg.address;
          realName = cfg.real_name;
          primary = true;
          mbsync = {
            enable = true;
            create = "both";
            expunge = "both";
            remove = "both";
            extraConfig.account.PipelineDepth = 50;
          };
          msmtp.enable = mkDefault cfg.enable;
          imap.host = cfg.imap.host;
          smtp.host = cfg.smtp.host;
          passwordCommand = let
            name = "mbsync-password-command";
          in "${pkgs.writeShellApplication {
            inherit name;
            runtimeInputs = [pkgs.coreutils];
            text = "cat ${cfg.password_secret}";
          }}/bin/${name}";
        };
      };
    };
  }
