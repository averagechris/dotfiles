{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.sideshow;
  system = pkgs.stdenv.hostPlatform.system;
  tomlFormat = pkgs.formats.toml {};
  inputPackage =
    if inputs ? sideshow && inputs.sideshow ? packages && builtins.hasAttr system inputs.sideshow.packages
    then inputs.sideshow.packages.${system}.sideshow or inputs.sideshow.packages.${system}.default
    else null;
  mkToolOptions = {
    description,
    defaultPackage,
    defaultEnable ? false,
  }: {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = defaultEnable;
      description = ''
        Write this tool into `~/.config/sideshow/config.toml` and optionally
        install its package.
      '';
    };

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = defaultPackage;
      description = "Package providing ${description}.";
    };

    path = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/current-system/sw/bin/${description}";
      description = ''
        Explicit executable path to write for this sideshow tool. When unset and
        the tool is enabled, the module uses the selected package's main binary.
      '';
    };

    install = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the selected package when this tool is enabled.";
    };
  };
  toolPath = tool:
    if tool.path != null
    then tool.path
    else if tool.enable && tool.package != null
    then lib.getExe tool.package
    else null;
  enabledToolPackage = tool: lib.optional (tool.enable && tool.install && tool.package != null) tool.package;
  generatedTools = lib.filterAttrs (_: value: value != null) {
    tailwindcss = toolPath cfg.tools.tailwindcss;
    ffmpeg = toolPath cfg.tools.ffmpeg;
    vhs = toolPath cfg.tools.vhs;
    aws = toolPath cfg.tools.aws;
  };
  generatedSettings =
    lib.optionalAttrs (generatedTools != {}) {
      tools = generatedTools;
    }
    // lib.optionalAttrs (cfg.srht.tokenCommand != null) {
      srht."token-cmd" = cfg.srht.tokenCommand;
    };
  mergedSettings = lib.recursiveUpdate generatedSettings cfg.settings;
in {
  options.dotfiles.sideshow = {
    enable = lib.mkEnableOption "sideshow HTML slide deck compiler and toolkit";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = inputPackage;
      defaultText = lib.literalExpression ''inputs.sideshow.packages.${pkgs.stdenv.hostPlatform.system}.sideshow'';
      description = ''
        sideshow CLI package to install. Defaults to the sideshow flake input
        when the host provides it.
      '';
    };

    settings = lib.mkOption {
      inherit (tomlFormat) type;
      default = {};
      description = ''
        Extra sideshow user configuration merged into the generated TOML. Values
        here override module-generated `[tools]` and `[srht]` entries.
      '';
    };

    configFile.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Write `~/.config/sideshow/config.toml` with configured tool paths and
        SourceHut token command settings.
      '';
    };

    tools = {
      tailwindcss = mkToolOptions {
        description = "tailwindcss";
        # sideshow shells out to Tailwind's v4 standalone CLI; nixpkgs exposes
        # the v4 package as tailwindcss_4. Override this option if a deck needs a
        # newer/different Tailwind binary before nixpkgs catches up.
        defaultPackage = pkgs.tailwindcss_4;
        defaultEnable = true;
      };
      ffmpeg = mkToolOptions {
        description = "ffmpeg";
        defaultPackage = pkgs.ffmpeg-headless;
      };
      vhs = mkToolOptions {
        description = "vhs";
        defaultPackage = pkgs.vhs;
      };
      aws = mkToolOptions {
        description = "aws";
        defaultPackage = pkgs.awscli2;
      };
    };

    srht.tokenCommand = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      example = ["pass" "show" "srht/pages-token"];
      description = ''
        Optional command written as `[srht].token-cmd`. sideshow uses it to get a
        SourceHut Pages token when `SRHT_TOKEN` is not set. Do not put plaintext
        tokens in the Nix store; point at a keyring/password-manager command.
      '';
    };

    opencode = {
      exposeTool = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Expose `sideshow` in OpenCode's generated agent tool note when OpenCode is enabled.";
      };

      skill.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the repo-managed sideshow OpenCode skill when OpenCode is enabled.";
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.package != null;
          message = "dotfiles.sideshow.enable requires dotfiles.sideshow.package or an inputs.sideshow flake input.";
        }
        {
          assertion = lib.all (tool: !tool.enable || tool.path != null || tool.package != null) [
            cfg.tools.tailwindcss
            cfg.tools.ffmpeg
            cfg.tools.vhs
            cfg.tools.aws
          ];
          message = "enabled dotfiles.sideshow.tools entries require either package or path.";
        }
      ];

      home.packages =
        lib.optional (cfg.package != null) cfg.package
        ++ enabledToolPackage cfg.tools.tailwindcss
        ++ enabledToolPackage cfg.tools.ffmpeg
        ++ enabledToolPackage cfg.tools.vhs
        ++ enabledToolPackage cfg.tools.aws;

      xdg.configFile."sideshow/config.toml" = lib.mkIf (cfg.configFile.enable && mergedSettings != {}) {
        source = tomlFormat.generate "sideshow-config.toml" mergedSettings;
      };
    }

    (lib.mkIf (config.programs.opencode.enable && cfg.opencode.exposeTool && cfg.package != null) {
      dotfiles.opencode.agentTools = lib.mkAfter [
        {
          inherit (cfg) package;
          name = "sideshow";
          description = "HTML slide deck CLI";
        }
      ];
    })

    (lib.mkIf (config.programs.opencode.enable && cfg.opencode.skill.enable) {
      programs.opencode.skills.sideshow-work-story = builtins.readFile ./opencode/skills/sideshow-work-story/SKILL.md;
    })
  ]);
}
