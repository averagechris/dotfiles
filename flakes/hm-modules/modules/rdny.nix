{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.rdny;
  system = pkgs.stdenv.hostPlatform.system;
  tomlFormat = pkgs.formats.toml {};
  inputPackage =
    if inputs ? rdny && inputs.rdny ? packages && builtins.hasAttr system inputs.rdny.packages
    then inputs.rdny.packages.${system}.rdny or inputs.rdny.packages.${system}.default
    else null;
  mkBinaryOptions = {
    description,
    defaultPackage ? null,
  }: {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Write this binary into `~/.config/rdny/config.toml`. When enabled and
        `path` is unset, the module uses the selected package's main binary.
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
      example = "/Applications/Helium.app/Contents/MacOS/Helium";
      description = ''
        Explicit executable path to write for this rdny binary. This is useful
        for non-Nix browser installations, especially on macOS.
      '';
    };

    install = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the selected package when this binary is enabled.";
    };
  };
  binaryPath = binary:
    if !binary.enable
    then null
    else if binary.path != null
    then binary.path
    else if binary.package != null
    then lib.getExe binary.package
    else null;
  enabledBinaryPackage = binary:
    lib.optional (binary.enable && binary.install && binary.package != null) binary.package;
  generatedBinaries = lib.filterAttrs (_: value: value != null) {
    chrome = binaryPath cfg.binaries.chrome;
    ffmpeg = binaryPath cfg.binaries.ffmpeg;
  };
  generatedConnect =
    lib.optionalAttrs (cfg.connect.default != null) {
      default = cfg.connect.default;
    }
    // lib.optionalAttrs (cfg.connect.targets != {}) {
      targets = cfg.connect.targets;
    };
  generatedSettings =
    lib.optionalAttrs (generatedBinaries != {}) {
      binaries = generatedBinaries;
    }
    // lib.optionalAttrs (generatedConnect != {}) {
      connect = generatedConnect;
    };
  mergedSettings = lib.recursiveUpdate generatedSettings cfg.settings;
in {
  options.dotfiles.rdny = {
    enable = lib.mkEnableOption "rdny browser automation CLI";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = inputPackage;
      defaultText = lib.literalExpression ''inputs.rdny.packages.${pkgs.stdenv.hostPlatform.system}.rdny'';
      description = ''
        rdny CLI package to install. Defaults to the rdny flake input when the
        host provides it.
      '';
    };

    settings = lib.mkOption {
      inherit (tomlFormat) type;
      default = {};
      description = ''
        Extra rdny user configuration merged into the generated TOML. Values
        here override module-generated `[binaries]` and `[connect]` entries.
      '';
    };

    configFile.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Write `~/.config/rdny/config.toml` from the module configuration.";
    };

    binaries = {
      chrome = mkBinaryOptions {
        description = "Chrome/Chromium/Helium browser binary";
      };

      ffmpeg = mkBinaryOptions {
        description = "ffmpeg binary used by `rdny stop-video`";
        defaultPackage = pkgs.ffmpeg;
      };
    };

    connect = {
      default = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "helium";
        description = "Default named target for `rdny connect` when no address is supplied.";
      };

      targets = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {};
        example = {
          helium = "127.0.0.1:9333";
        };
        description = "Named `rdny connect` targets, each as `<host>:<port>`.";
      };
    };

    environment = {
      stateDir = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/home/chris/.local/state/rdny-agent";
        description = ''
          Optional `RDNY_STATE_DIR` exported in the user's login environment.
          Leave unset to let rdny choose its platform default.
        '';
      };

      chromeArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["--headless=new" "--disable-gpu"];
        description = ''
          Optional extra browser flags exported as `RDNY_CHROME_ARGS`. rdny
          splits this value on ASCII whitespace, so keep each item free of
          embedded spaces.
        '';
      };
    };

    opencode = {
      exposeTool = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Expose `rdny` in OpenCode's generated agent tool note when OpenCode is enabled.";
      };

      skill.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the repo-managed rdny OpenCode skill when OpenCode is enabled.";
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.package != null;
          message = "dotfiles.rdny.enable requires dotfiles.rdny.package or an inputs.rdny flake input.";
        }
        {
          assertion = lib.all (binary: !binary.enable || binary.path != null || binary.package != null) [
            cfg.binaries.chrome
            cfg.binaries.ffmpeg
          ];
          message = "enabled dotfiles.rdny.binaries entries require either package or path.";
        }
      ];

      home.packages =
        lib.optional (cfg.package != null) cfg.package
        ++ enabledBinaryPackage cfg.binaries.chrome
        ++ enabledBinaryPackage cfg.binaries.ffmpeg;

      xdg.configFile."rdny/config.toml" = lib.mkIf (cfg.configFile.enable && mergedSettings != {}) {
        source = tomlFormat.generate "rdny-config.toml" mergedSettings;
      };

      home.sessionVariables =
        lib.optionalAttrs (cfg.environment.stateDir != null) {
          RDNY_STATE_DIR = cfg.environment.stateDir;
        }
        // lib.optionalAttrs (cfg.environment.chromeArgs != []) {
          RDNY_CHROME_ARGS = lib.concatStringsSep " " cfg.environment.chromeArgs;
        };
    }

    (lib.mkIf (config.programs.opencode.enable && cfg.opencode.exposeTool && cfg.package != null) {
      dotfiles.opencode.agentTools = lib.mkAfter [
        {
          inherit (cfg) package;
          name = "rdny";
          description = "browser automation CLI";
        }
      ];
    })

    (lib.mkIf (config.programs.opencode.enable && cfg.opencode.skill.enable) {
      programs.opencode.skills.rdny-browser = builtins.readFile ./opencode/skills/rdny-browser/SKILL.md;
    })
  ]);
}
