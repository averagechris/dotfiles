{lib, ...}: {
  options.programs.helix.terminal = {
    flavor = lib.mkOption {
      type = lib.types.enum ["kitty" "wezterm"];
      default = "wezterm";
      description = "Terminal flavor to use for terminal integration features";
    };
  };
}
