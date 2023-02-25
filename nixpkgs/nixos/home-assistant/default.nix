{pkgs, ...}: {
  services.home-assistant = let
    package =
      (pkgs.home-assistant.override {
        extraPackages = pythonPackages:
          with pythonPackages; [
            aiounifi # ubiquity router
            aiowebostv # lg webOS tv
            psycopg2 # postgres
            pyatv # apple tv
            pyicloud # apple icloud
            python-miio # roborock
            securetar # backup
          ];
      })
      .overrideAttrs (oldAttrs: {
        doInstallCheck = false;
      });
  in {
    inherit package;
    enable = true;
    extraComponents = [
      "met"
      "radio_browser"
    ];
    config = {
      # Includes dependencies for a basic setup
      # https://www.home-assistant.io/integrations/default_config/
      default_config = {};
      recorder.db_url = "postgresql://@/hass";
    };
  };

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_14;
    ensureDatabases = ["hass"];
    ensureUsers = [
      {
        name = "hass";
        ensurePermissions = {
          "DATABASE hass" = "ALL PRIVILEGES";
        };
      }
    ];
  };
}
