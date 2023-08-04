{pkgs, ...}: let
  iniFormat = pkgs.formats.ini {};
  awscliConfig = {
    sso_start_url = "https://sureplatform.awsapps.com/start";
    sso_region = "us-east-1";
    region = "us-east-1";
    output = "json";
  };
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

  programs.zsh = {
    sessionVariables = {
      AWS_PROFILE = "qa";
    };
  };
}
