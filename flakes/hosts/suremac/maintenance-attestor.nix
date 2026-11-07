{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.maintenanceAttestor;
  inherit (config.users.users.chris) home;
  stateDir = "${home}/.local/state/dotfiles-maintenance-attestor";
  pythonRoot = pkgs.runCommand "dotfiles-maintenance-python" {} ''
    site="$out/lib/python${pkgs.python3.pythonVersion}/site-packages"
    mkdir -p "$site"
    cp -R ${../../../scripts/maintenance} "$site/maintenance"
  '';
  attestor = pkgs.writeShellApplication {
    name = "dotfiles-maintenance-attestor";
    runtimeInputs = [pkgs.python3 pkgs.curl pkgs.coreutils];
    text = ''
      set -euo pipefail
      export PYTHONPATH=${lib.escapeShellArg "${pythonRoot}/lib/python${pkgs.python3.pythonVersion}/site-packages"}
      exec python -m maintenance.host tick \
        --state ${lib.escapeShellArg stateDir} \
        --app-login ${lib.escapeShellArg cfg.appLogin} \
        --attestor-login ${lib.escapeShellArg cfg.attestorLogin} \
        --token-file ${lib.escapeShellArg cfg.tokenFile}
    '';
  };
in {
  options.dotfiles.maintenanceAttestor = {
    enable = lib.mkEnableOption "Suremac certificate hold attestation for dotfiles maintenance";

    appLogin = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "GitHub login of the maintenance App that authors candidate PRs.";
    };

    attestorLogin = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "GitHub login authorized to dispatch host attestation workflows.";
    };

    tokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Absolute path to a separately provisioned mode-0600 GitHub token file.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.appLogin != "" && lib.hasSuffix "[bot]" cfg.appLogin;
        message = "dotfiles.maintenanceAttestor.appLogin must be the maintenance App bot login.";
      }
      {
        assertion = builtins.match "[a-zA-Z0-9]+(-[a-zA-Z0-9]+)*" cfg.attestorLogin != null;
        message = "dotfiles.maintenanceAttestor.attestorLogin must be the approved scoped-token user's GitHub login.";
      }
      {
        assertion = cfg.tokenFile != null && lib.hasPrefix "/" cfg.tokenFile;
        message = "dotfiles.maintenanceAttestor.tokenFile must be an absolute explicitly provisioned path.";
      }
    ];

    launchd.user.agents.dotfiles-maintenance-attestor.serviceConfig = {
      ProgramArguments = [(lib.getExe attestor)];
      StartInterval = 900;
      RunAtLoad = true;
      ProcessType = "Background";
      LowPriorityIO = true;
      StandardOutPath = "${home}/Library/Logs/dotfiles-maintenance-attestor.log";
      StandardErrorPath = "${home}/Library/Logs/dotfiles-maintenance-attestor.log";
    };
  };
}
