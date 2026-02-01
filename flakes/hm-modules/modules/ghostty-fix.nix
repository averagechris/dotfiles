# Fix for ghostty validation hanging during home-manager activation
# This module must be imported AFTER the ghostty module to override its settings
{
  config,
  lib,
  ...
}: {
  # Override ghostty config to disable validation during activation
  # The validation runs 'ghostty +validate-config' which requires a display
  # We set onChange to "true" (no-op) to prevent the hang
  xdg.configFile."ghostty/config" = lib.mkIf (config.programs.ghostty.enable or false) {
    onChange = lib.mkForce "true";
  };
}
