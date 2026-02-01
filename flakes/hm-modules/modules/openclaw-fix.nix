# Fix for nix-openclaw node systemd service to prevent activation timeouts
{
  config,
  lib,
  pkgs,
  ...
}: {
  # This fixes the openclaw node systemd service by adding ConditionEnvironment
  # to prevent it from trying to start during home-manager activation
  config = lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && config.programs.openclaw?nodes) {
    systemd.user.services = lib.mkMerge (
      lib.mapAttrsToList (name: node: 
        lib.optionalAttrs (node.enable or false && node.systemd.enable or false) {
          "${node.systemd.unitName or "openclaw-node-${name}"}" = {
            Unit = {
              # Only start when graphical session is actually ready
              # This prevents activation timeouts
              ConditionEnvironment = [ "WAYLAND_DISPLAY" "DISPLAY" ];
            };
          };
        }
      ) config.programs.openclaw.nodes
    );
  };
}
