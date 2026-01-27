{pkgs, ...}: let
  iniFormat = pkgs.formats.ini {};
  awscliConfig = {
    sso_start_url = "https://sureplatform.awsapps.com/start";
    sso_region = "us-east-1";
    region = "us-east-1";
    output = "json";
  };

  refresh-poetry-auth = pkgs.writeShellScriptBin "refresh-poetry-auth" ''
    set -euo pipefail

    echo "Refreshing poetry auth token for CodeArtifact..."

    # Login to AWS SSO
    aws sso login --profile registries-read

    # Get auth token and configure poetry
    poetry config http-basic.codeartifact aws "$(aws codeartifact get-authorization-token \
      --profile registries-read \
      --domain sure \
      --query authorizationToken \
      --output text \
      --duration-seconds 0)"

    echo "Poetry auth token refreshed successfully"
  '';
in {
  home.file.".aws/config".source = iniFormat.generate "awscli.config" {
    "profile qa" =
      awscliConfig
      // {
        sso_account_id = "312107431298";
        sso_role_name = "non-production-backend-access";
      };

    "profile sandbox" =
      awscliConfig
      // {
        sso_account_id = "312107431298";
        sso_role_name = "non-production-backend-access";
      };

    "profile registries-read" =
      awscliConfig
      // {
        sso_account_id = "348777858795";
        sso_role_name = "RegistryReadAccess";
      };
  };

  home.packages = [refresh-poetry-auth];

  # Auto-refresh poetry auth 3 minutes after login and periodically
  launchd.agents.refresh-poetry-auth-auto = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.bash}/bin/bash"
        "-c"
        "sleep 180 && ${refresh-poetry-auth}/bin/refresh-poetry-auth"
      ];
      RunAtLoad = true; # Run when user logs in
      KeepAlive = false;
      EnvironmentVariables = {
        PATH = "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:${pkgs.awscli2}/bin:${pkgs.poetry}/bin";
      };
    };
  };

  # Periodic refresh twice daily
  launchd.agents.refresh-poetry-auth-periodic = {
    enable = true;
    config = {
      ProgramArguments = ["${refresh-poetry-auth}/bin/refresh-poetry-auth"];
      StartCalendarInterval = [
        {
          Hour = 9;
          Minute = 0;
        } # 9 AM
        {
          Hour = 17;
          Minute = 0;
        } # 5 PM
      ];
      EnvironmentVariables = {
        PATH = "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:${pkgs.awscli2}/bin:${pkgs.poetry}/bin";
      };
    };
  };

  programs.zsh = {
    sessionVariables = {
      AWS_PROFILE = "qa";
    };
  };
}
