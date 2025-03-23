{
  dotfiles_lib,
  lib,
  ...
}: {
  options.programs.helix.terminal = {
    flavor = lib.mkOption {
      type = lib.types.enum ["kitty" "wezterm"];
      default = "kitty";
      description = "Terminal flavor to use for terminal integration features";
    };
  };
}
