{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.ctx;
  indexCommand = pkgs.writeShellApplication {
    name = "ctx-index";
    runtimeInputs = [cfg.package];
    text = ''
      ctx setup --catalog-only --progress none
      ctx import --all --resume --progress none
    '';
  };
in {
  options.dotfiles.ctx = {
    enable = lib.mkEnableOption "Ctx local agent-history search CLI";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      example = lib.literalExpression ''inputs.ctx.packages.''${pkgs.stdenv.hostPlatform.system}.ctx'';
      description = ''
        Ctx CLI package to install. Hosts with the ctx flake input should pass
        that package explicitly.
      '';
    };

    index = {
      enable = lib.mkEnableOption "frequent background ctx history indexing";

      intervalSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 300;
        description = ''
          Number of seconds between background ctx index refreshes. The default
          is intentionally frequent so local agent-history search stays fresh;
          launchd/systemd timers do not wake a sleeping laptop.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.package != null;
        message = "dotfiles.ctx.enable requires dotfiles.ctx.package.";
      }
    ];

    home.packages = [cfg.package];

    launchd.agents.ctx-index = lib.mkIf (cfg.index.enable && pkgs.stdenv.hostPlatform.isDarwin) {
      enable = true;
      config = {
        ProgramArguments = [
          (lib.getExe indexCommand)
        ];
        RunAtLoad = true;
        StartInterval = cfg.index.intervalSeconds;
        ProcessType = "Background";
        LowPriorityIO = true;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/ctx-index.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/ctx-index.log";
      };
    };

    systemd.user.services.ctx-index = lib.mkIf (cfg.index.enable && pkgs.stdenv.hostPlatform.isLinux) {
      Unit = {
        Description = "Refresh ctx local agent-history index";
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe indexCommand;
        Nice = 10;
        IOSchedulingClass = "idle";
      };
    };

    systemd.user.timers.ctx-index = lib.mkIf (cfg.index.enable && pkgs.stdenv.hostPlatform.isLinux) {
      Unit = {
        Description = "Refresh ctx local agent-history index frequently";
      };
      Timer = {
        OnBootSec = "1m";
        OnUnitActiveSec = "${toString cfg.index.intervalSeconds}s";
        Unit = "ctx-index.service";
      };
      Install = {
        WantedBy = ["timers.target"];
      };
    };
  };
}
