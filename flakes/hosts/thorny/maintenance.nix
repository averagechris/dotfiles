# Dormant, separately credentialed controller for owner-approved maintenance.
# Imported by the Thorny host; nothing is enabled until dotfiles.maintenance.enable.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.maintenance;
  stateDir = "/var/lib/dotfiles-maintenance";
  requestDir = "/var/lib/dotfiles-maintenance-requests";
  source = ../../../scripts/maintenance;
  maintenanceRuntime = pkgs.runCommand "dotfiles-maintenance-runtime" {} ''
    mkdir -p "$out/maintenance"
    cp -R ${source}/. "$out/maintenance/"
    chmod -R a-w "$out"
  '';
  requestPackage = pkgs.writeShellApplication {
    name = "michi-maintenance";
    runtimeInputs = [pkgs.python3];
    text = ''
      export PYTHONPATH="${maintenanceRuntime}"
      exec ${pkgs.python3}/bin/python ${maintenanceRuntime}/maintenance/cli.py request \
        --requests ${requestDir} "$@"
    '';
  };
  controllerPackage = pkgs.writeShellApplication {
    name = "dotfiles-maintenance-controller";
    runtimeInputs = [pkgs.python3];
    text = ''
      export PYTHONPATH="${maintenanceRuntime}"
      exec ${pkgs.python3}/bin/python ${maintenanceRuntime}/maintenance/cli.py "$@"
    '';
  };
in {
  options.dotfiles.maintenance = {
    enable = lib.mkEnableOption "the isolated Dotfiles maintenance controller";
    appLogin = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "GitHub App bot login used to identify maintenance pull requests.";
    };
    attestorLogin = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Separately authorized GitHub login that may publish suremac certificate evidence.";
    };
    githubAppId = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "GitHub App ID used by the controller to mint short-lived installation tokens.";
    };
    githubInstallationId = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Installation ID of the repository-scoped maintenance GitHub App.";
    };
    githubAppKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Root-readable GitHub App private key used only by the controller.";
    };
    openaiApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Root-readable source file for the maintenance review API key.";
    };
    telegramBotTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Root-readable Telegram bot token credential for the alert delivery unit.";
    };
    telegramOwnerIdFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Root-readable numeric owner ID credential for the alert delivery unit.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = "Owner-facing michi-maintenance request CLI package.";
    };
  };

  config = lib.mkMerge [
    {dotfiles.maintenance.package = requestPackage;}
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = lib.hasSuffix "[bot]" cfg.appLogin && builtins.match "[a-zA-Z0-9]+(-[a-zA-Z0-9]+)*" (lib.removeSuffix "[bot]" cfg.appLogin) != null;
          message = "dotfiles.maintenance.appLogin must be the configured GitHub App bot login.";
        }
        {
          assertion = builtins.match "[a-zA-Z0-9-]+" cfg.attestorLogin != null;
          message = "dotfiles.maintenance.attestorLogin must identify the approved suremac evidence publisher.";
        }
        {
          assertion = builtins.match "[0-9]+" cfg.githubAppId != null && builtins.match "[0-9]+" cfg.githubInstallationId != null && cfg.githubAppKeyFile != null;
          message = "GitHub App ID, installation ID, and private key file are required when maintenance is enabled.";
        }
        {
          assertion = cfg.openaiApiKeyFile != null;
          message = "dotfiles.maintenance.openaiApiKeyFile is required when maintenance is enabled.";
        }
        {
          assertion = cfg.telegramBotTokenFile != null && cfg.telegramOwnerIdFile != null;
          message = "Telegram credential files are required when maintenance is enabled.";
        }
      ];
      users.groups.dotfiles-maintenance-requests = {};
      users.users.zeroclaw-home.extraGroups = ["dotfiles-maintenance-requests"];

      systemd.tmpfiles.rules = [
        "d ${stateDir} 0700 dotfiles-maintenance dotfiles-maintenance -"
        "d ${requestDir} 2770 root dotfiles-maintenance-requests -"
      ];
      users.users.dotfiles-maintenance = {
        isSystemUser = true;
        group = "dotfiles-maintenance";
        description = "Isolated Dotfiles maintenance controller";
        home = stateDir;
        createHome = false;
        extraGroups = ["dotfiles-maintenance-requests"];
      };
      users.groups.dotfiles-maintenance = {};

      environment.systemPackages = [requestPackage];
      systemd.services.dotfiles-maintenance = {
        description = "Isolated Dotfiles maintenance controller tick";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        path = [pkgs.openssl];
        serviceConfig = {
          Type = "oneshot";
          User = "dotfiles-maintenance";
          Group = "dotfiles-maintenance";
          SupplementaryGroups = ["dotfiles-maintenance-requests"];
          WorkingDirectory = stateDir;
          ExecStart = lib.escapeShellArgs [
            (lib.getExe controllerPackage)
            "tick"
            "--state"
            stateDir
            "--app-login"
            cfg.appLogin
            "--app-id"
            cfg.githubAppId
            "--installation-id"
            cfg.githubInstallationId
            "--requests"
            requestDir
            "--attestor-login"
            cfg.attestorLogin
          ];
          LoadCredential = [
            "github-app-key:${toString cfg.githubAppKeyFile}"
            "openai-api-key:${toString cfg.openaiApiKeyFile}"
          ];
          UMask = "0007";
          TimeoutStartSec = "10min";
          NoNewPrivileges = true;
          PrivateUsers = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectProc = "invisible";
          InaccessiblePaths = ["/var/lib/zeroclaw-home"];
          RestrictNamespaces = true;
          RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
          RestrictSUIDSGID = true;
          LockPersonality = true;
          CapabilityBoundingSet = "";
          ReadWritePaths = [stateDir requestDir];
          StateDirectory = "dotfiles-maintenance";
          StateDirectoryMode = "0700";
          Environment = ["PYTHONPATH=${maintenanceRuntime}"];
        };
      };
      systemd.timers.dotfiles-maintenance = {
        description = "Periodic Dotfiles maintenance controller tick";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "5m";
          OnUnitActiveSec = "15m";
          Persistent = true;
        };
      };

      systemd.services.dotfiles-maintenance-notify = {
        description = "Deliver private Dotfiles maintenance alerts to the owner";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        serviceConfig = {
          Type = "oneshot";
          User = "dotfiles-maintenance";
          Group = "dotfiles-maintenance";
          WorkingDirectory = stateDir;
          ExecStart = lib.escapeShellArgs [
            "${pkgs.python3}/bin/python"
            "${maintenanceRuntime}/maintenance/notify.py"
            "deliver"
            "--state"
            "${stateDir}/alerts"
          ];
          LoadCredential = [
            "bot-token:${toString cfg.telegramBotTokenFile}"
            "owner-id:${toString cfg.telegramOwnerIdFile}"
          ];
          UMask = "0077";
          TimeoutStartSec = "2min";
          NoNewPrivileges = true;
          PrivateUsers = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectProc = "invisible";
          InaccessiblePaths = ["/var/lib/zeroclaw-home"];
          RestrictNamespaces = true;
          RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
          RestrictSUIDSGID = true;
          LockPersonality = true;
          CapabilityBoundingSet = "";
          ReadWritePaths = [stateDir];
          StateDirectory = "dotfiles-maintenance";
          StateDirectoryMode = "0700";
          Environment = ["PYTHONPATH=${maintenanceRuntime}"];
        };
      };
      systemd.timers.dotfiles-maintenance-notify = {
        description = "Periodic delivery of Dotfiles maintenance alerts";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "1m";
          OnUnitActiveSec = "30s";
          Persistent = true;
        };
      };
      systemd.paths.dotfiles-maintenance-requests = {
        description = "Run maintenance controller for explicit owner requests";
        wantedBy = ["paths.target"];
        pathConfig = {
          PathChanged = "${requestDir}/request.json";
          Unit = "dotfiles-maintenance.service";
        };
      };
    })
  ];
}
