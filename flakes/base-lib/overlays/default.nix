# Empty overlay - titlecase is now handled directly in mkNixosHost/mkDarwinHost
{
  inputs,
  nixpkgs,
  titlecase,
}: {
  default = final: prev: {
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
