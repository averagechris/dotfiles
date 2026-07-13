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
  nullableUnsigned = description:
    lib.mkOption {
      type = lib.types.nullOr lib.types.ints.unsigned;
      default = null;
      inherit description;
    };
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
  chromePaths = binary: let
    primary = binaryPath binary;
  in
    lib.optional (primary != null) primary ++ binary.fallbackPaths;
  enabledBinaryPackage = binary:
    lib.optional (binary.enable && binary.install && binary.package != null) binary.package;
  generatedBinaries = lib.filterAttrs (_: value: value != null) {
    chrome =
      if cfg.binaries.chrome.enable
      then chromePaths cfg.binaries.chrome
      else null;
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
  quotaSessionVariables = lib.mapAttrs (_: toString) (lib.filterAttrs (_: value: value != null) {
    RDNY_MAX_DOWNLOAD_BYTES = cfg.environment.maxDownloadBytes;
    RDNY_MAX_SCREENCAST_FRAME_BYTES = cfg.environment.maxScreencastFrameBytes;
    RDNY_MAX_RECORDING_FRAMES = cfg.environment.maxRecordingFrames;
    RDNY_MAX_RECORDING_SECONDS = cfg.environment.maxRecordingSeconds;
    RDNY_MAX_RECORDING_BYTES = cfg.environment.maxRecordingBytes;
    RDNY_MIN_FREE_DISK_BYTES = cfg.environment.minFreeDiskBytes;
  });
  rdnyCompletions = pkgs.runCommand "rdny-completions" {} ''
    install -dm755 \
      $out/share/bash-completion/completions \
      $out/share/fish/vendor_completions.d \
      $out/share/zsh/site-functions

    ${lib.getExe cfg.package} completion bash > $out/share/bash-completion/completions/rdny
    ${lib.getExe cfg.package} completion fish > $out/share/fish/vendor_completions.d/rdny.fish
    ${lib.getExe cfg.package} completion zsh > $out/share/zsh/site-functions/_rdny
  '';
  rdnySkillSource =
    if cfg.package != null && cfg.package ? src
    then cfg.package.src + "/skills/rdny-browser/SKILL.md"
    else null;
in {
  imports = [./agent-skills.nix];

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

    completions.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install generated rdny bash, fish, and zsh completions in the standard
        Home Manager profile completion directories for enabled shells.
      '';
    };

    binaries = {
      chrome =
        mkBinaryOptions {
          description = "Chrome/Chromium/Helium browser binary";
        }
        // {
          fallbackPaths = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            example = ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"];
            description = ''
              Additional Chrome-family executable paths tried in order after the
              primary `path` or package. Configuring any paths replaces rdny's
              built-in platform discovery, so list every desired fallback here.
            '';
          };
        };

      ffmpeg = mkBinaryOptions {
        description = "ffmpeg binary used by `rdny stop-video`";
        # Keep every dotfiles ffmpeg consumer on the same headless output so
        # Home Manager never combines competing bin/ffmpeg providers.
        defaultPackage = pkgs.ffmpeg-headless;
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

      maxDownloadBytes = nullableUnsigned ''
        Optional `RDNY_MAX_DOWNLOAD_BYTES` limit for a single download. Leave
        unset to use rdny's 256 MiB default.
      '';
      maxScreencastFrameBytes = nullableUnsigned ''
        Optional `RDNY_MAX_SCREENCAST_FRAME_BYTES` per-frame recording limit.
        Leave unset to use rdny's 8 MiB default.
      '';
      maxRecordingFrames = nullableUnsigned ''
        Optional `RDNY_MAX_RECORDING_FRAMES` recording frame limit. Leave unset
        to use rdny's 18,000-frame default.
      '';
      maxRecordingSeconds = nullableUnsigned ''
        Optional `RDNY_MAX_RECORDING_SECONDS` recording duration limit. Leave
        unset to use rdny's 1,800-second default.
      '';
      maxRecordingBytes = nullableUnsigned ''
        Optional `RDNY_MAX_RECORDING_BYTES` total recording limit. Leave unset
        to use rdny's 512 MiB default.
      '';
      minFreeDiskBytes = nullableUnsigned ''
        Optional `RDNY_MIN_FREE_DISK_BYTES` reserve required while recording.
        Leave unset to use rdny's 256 MiB default.
      '';
    };

    opencode = {
      exposeTool = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Expose `rdny` in OpenCode's generated agent tool note when OpenCode is enabled.";
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
          assertion =
            (!cfg.binaries.chrome.enable
              || cfg.binaries.chrome.path != null
              || cfg.binaries.chrome.package != null
              || cfg.binaries.chrome.fallbackPaths != [])
            && (!cfg.binaries.ffmpeg.enable
              || cfg.binaries.ffmpeg.path != null
              || cfg.binaries.ffmpeg.package != null);
          message = "enabled dotfiles.rdny.binaries entries require a package, path, or Chrome fallbackPaths entry.";
        }
      ];

      home.packages =
        lib.optional (cfg.package != null) cfg.package
        ++ lib.optional (cfg.package != null && cfg.completions.enable) rdnyCompletions
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
        }
        // quotaSessionVariables;

      dotfiles.agentSkills.rdny-browser.source = lib.mkDefault rdnySkillSource;
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
  ]);
}
