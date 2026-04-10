# Empty overlay - titlecase is now handled directly in mkNixosHost/mkDarwinHost
{
  inputs,
  nixpkgs,
  titlecase,
}: {
  default = final: prev: {
    rodney = prev.buildGoModule rec {
      pname = "rodney";
      version = "0.4.0";

      src = prev.fetchFromGitHub {
        owner = "simonw";
        repo = pname;
        rev = "9e7ae93900bcb5316d02623706bc8861feec836f";
        hash = "sha256-/iGsaMfK8zeUkTXwU63mAAb4VpsllG87EH8ycoFZs5k=";
      };

      vendorHash = "sha256-h4U43W3hLoF+p25/jNRaW8okeEzAZQEmKtwB5l4kGW4=";

      subPackages = ["."];

      doCheck = false;

      meta = with prev.lib; {
        description = "CLI for interacting with Chrome from agents and scripts";
        homepage = "https://github.com/simonw/rodney";
        license = licenses.asl20;
        mainProgram = "rodney";
        platforms = platforms.unix;
      };
    };

    showboat = prev.buildGoModule rec {
      pname = "showboat";
      version = "0.6.1";

      src = prev.fetchFromGitHub {
        owner = "simonw";
        repo = pname;
        rev = "d531261b8faf0c388b02c7891d50f1f47c3e2b52";
        hash = "sha256-yYK6j6j7OgLABHLOSKlzNnm2AWzM2Ig76RJypBsBnkI=";
      };

      vendorHash = "sha256-mGKxBRU5TPgdmiSx0DHEd0Ys8gsVD/YdBfbDdSVpC3U=";

      ldflags = ["-X main.version=${version}"];

      subPackages = ["."];

      doCheck = false;

      meta = with prev.lib; {
        description = "CLI for creating executable documents that capture agent work";
        homepage = "https://github.com/simonw/showboat";
        license = licenses.asl20;
        mainProgram = "showboat";
        platforms = platforms.unix;
      };
    };

    # Patch for nix-openclaw to add ConditionEnvironment to node systemd service
    # This prevents home-manager activation timeouts
    nix-openclaw =
      prev.nix-openclaw
      // {
        homeManagerModules =
          prev.nix-openclaw.homeManagerModules
          // {
            openclaw = {
              config,
              lib,
              pkgs,
              ...
            }: let
              originalModule = import ../../nix-openclaw/nix/modules/home-manager/openclaw.nix {inherit config lib pkgs;};
            in
              originalModule
              // {
                config =
                  originalModule.config
                  // {
                    systemd = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
                      user.services = lib.mkMerge (lib.mapAttrsToList (
                          name: node:
                            lib.optionalAttrs node.systemd.enable {
                              "${node.systemd.unitName}" = {
                                Unit = {
                                  ConditionEnvironment = ["WAYLAND_DISPLAY" "DISPLAY"];
                                };
                              };
                            }
                        )
                        config.programs.openclaw.nodes);
                    };
                  };
              };
          };
      };
  };
}
