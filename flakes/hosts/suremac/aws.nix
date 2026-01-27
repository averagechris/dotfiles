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

  # NOTE: Launchd agents for auto-refresh removed due to poetry build issues in nixpkgs.
  # Run `refresh-poetry-auth` manually when needed.

  programs.zsh = {
    sessionVariables = {
      AWS_PROFILE = "qa";
    };
  };
}
