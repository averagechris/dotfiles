{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.gander;
  tomlFormat = pkgs.formats.toml {};
  system = pkgs.stdenv.hostPlatform.system;
  inputPackage =
    if inputs ? gander && inputs.gander ? packages && builtins.hasAttr system inputs.gander.packages
    then inputs.gander.packages.${system}.default
    else null;

  colemakKeybindings = {
    move-down = ["n" "down"];
    move-up = ["e" "up"];
    target-picker-down = ["down" "ctrl-n"];
    target-picker-up = ["up" "ctrl-e"];
    next-unviewed = ["]"];
    previous-unviewed = ["["];
    next-comment = ["l"];
    previous-comment = ["L"];
    collapse-fold = ["m" "left"];
    expand-fold = ["i" "right"];
  };

  defaultSettings = {
    keybindings = colemakKeybindings;
    # Summon opencode from the TUI with `@` (or via autostart). The gander
    # MCP server registered in opencode covers the split-pane flow; this
    # covers the "don't leave the review" flow.
    agent.command = "opencode run";
  };
in {
  options.dotfiles.gander = {
    enable = lib.mkEnableOption "Gander jj review TUI";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = inputPackage;
      defaultText = lib.literalExpression ''inputs.gander.packages.${pkgs.stdenv.hostPlatform.system}.default'';
      description = ''
        Gander package to install. Defaults to the gander flake input when the
        host provides it.
      '';
    };

    settings = lib.mkOption {
      inherit (tomlFormat) type;
      default = {};
      example = lib.literalExpression ''
        {
          artifact.on_tui_quit = "write";
          generated.presets = ["lockfiles"];
          keybindings.move-down = ["n" "down"];
        }
      '';
      description = ''
        Additional settings written to `~/.config/gander/config.toml`. Values
        follow Gander's TOML config schema and are merged over the dotfiles
        Colemak defaults.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.package != null;
        message = "dotfiles.gander.enable requires dotfiles.gander.package or an inputs.gander flake input.";
      }
    ];

    home.packages = [cfg.package];

    xdg.configFile."gander/config.toml".source = tomlFormat.generate "gander-config.toml" (lib.recursiveUpdate defaultSettings cfg.settings);
  };
}
