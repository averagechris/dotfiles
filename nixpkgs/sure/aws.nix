{
  config,
  pkgs,
  ...
}: let
  iniFormat = pkgs.formats.ini {};
  awscliConfig = {
    sso_start_url = "https://sureplatform.awsapps.com/start";
    sso_region = "us-east-1";
    region = "us-east-1";
    output = "json";
  };
in {
  config.home.file.".aws/config".source = iniFormat.generate "awscli.config" {
    "profile s" =
      awscliConfig
      // {
        sso_account_id = "818549452766";
        sso_role_name = "production-backend-access";
      };

    "profile in-production" =
      awscliConfig
      // {
        sso_account_id = "421705037700";
        sso_role_name = "production-backend-access";
      };

    "profile in-qa" =
      awscliConfig
      // {
        sso_account_id = "713190844401";
        sso_role_name = "non-production-backend-access";
      };

    "profile registries-read" =
      awscliConfig
      // {
        sso_account_id = "348777858795";
        sso_role_name = "RegistryReadAccess";
      };

    "profile non-production-connect" =
      awscliConfig
      // {
        sso_account_id = "186258024085";
        sso_role_name = "non-production-backend-access";
      };
  };

  config.programs.zsh = {
    sessionVariables = {
      AWS_PROFILE = "in-qa";
    };
  };

  config.home.packages = with pkgs; [
    awscli2
  ];
}
