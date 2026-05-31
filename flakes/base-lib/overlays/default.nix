# Empty overlay - titlecase is now handled directly in mkNixosHost/mkDarwinHost
{
  inputs,
  nixpkgs,
  titlecase,
  opencode ? null,
}: {
  default = final: prev: {
    opencode =
      if opencode != null && builtins.hasAttr prev.stdenv.hostPlatform.system opencode.packages
      then let
        inherit (prev.stdenv.hostPlatform) system;
        rev = opencode.shortRev or opencode.dirtyShortRev or "dirty";
        upstreamHashes = builtins.fromJSON (builtins.readFile "${opencode}/nix/hashes.json");
        nodeModulesHashOverrides = {
          # Upstream dev changed transitive dependency output without updating
          # nix/hashes.json for this revision. Keep this scoped to the exact
          # revision so future upstream hash updates are used automatically.
          "3b7a5e783d59e8986dca6e5df48663613fa80722" = {
            aarch64-darwin = "sha256-81IAmdjiYZz8IgMJt0+VxzdOS80gTHc5SendwEW/vD4=";
          };
        };
        node_modules = final.callPackage "${opencode}/nix/node_modules.nix" {
          inherit rev;
          hash =
            (nodeModulesHashOverrides.${opencode.rev or ""} or {}).${system} or upstreamHashes.nodeModules.${system};
        };
      in
        final.callPackage "${opencode}/nix/opencode.nix" {
          inherit node_modules;
        }
      else prev.opencode;

    pi-coding-agent = final.callPackage ../packages/pi-coding-agent.nix {};
    pi = final.pi-coding-agent;
    coderabbit-cli = final.callPackage ../packages/coderabbit-cli.nix {};

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
