{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.rustDevCache;

  # Run the sccache server supervised in the foreground with a clean launchd
  # environment. Without this, the server is auto-started by whichever compile
  # happens first and inherits that process's environment; a server started
  # inside a nix shell (where DEVELOPER_DIR points at the nix Apple SDK)
  # poisons every later C compile through /usr/bin/cc's xcselect shim with
  # "error: tool 'clang' not found".
  serverScript = pkgs.writeShellApplication {
    name = "dotfiles-sccache-server";
    runtimeInputs = [
      pkgs.sccache
    ];
    text = ''
      export SCCACHE_DIR=${lib.escapeShellArg cfg.sccache.directory}
      export SCCACHE_CACHE_SIZE=${lib.escapeShellArg cfg.sccache.cacheSize}
      # Never idle out: an exited server would get lazily restarted by an
      # arbitrary client with an arbitrary environment.
      export SCCACHE_IDLE_TIMEOUT=0
      export SCCACHE_NO_DAEMON=1

      # Take over from any rogue server started by a client.
      sccache --stop-server >/dev/null 2>&1 || true
      exec sccache --start-server
    '';
  };

  cleanupScript = pkgs.writeShellApplication {
    name = "dotfiles-dev-cache-cleanup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.docker-client
      pkgs.sccache
    ];
    text = ''
      set -uo pipefail

      log() {
        printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
      }

      export SCCACHE_DIR=${lib.escapeShellArg cfg.sccache.directory}
      export SCCACHE_CACHE_SIZE=${lib.escapeShellArg cfg.sccache.cacheSize}

      log "sccache stats (server is managed by the sccache-server launchd agent)"
      sccache --show-stats || true

      if ! docker info >/dev/null 2>&1; then
        log "docker daemon is unavailable; skipping Docker/OrbStack cleanup"
        exit 0
      fi

      log "docker disk usage before cleanup"
      docker system df || true

      log "pruning Docker/OrbStack builder cache older than ${cfg.docker.retention} with max-used-space ${cfg.docker.builderMaxUsedSpace}"
      docker builder prune \
        --all \
        --force \
        --filter ${lib.escapeShellArg "until=${cfg.docker.retention}"} \
        --max-used-space ${lib.escapeShellArg cfg.docker.builderMaxUsedSpace} || true

      log "pruning stopped containers, dangling images, and unused networks older than ${cfg.docker.retention}"
      docker container prune --force --filter ${lib.escapeShellArg "until=${cfg.docker.retention}"} || true
      docker image prune --force --filter ${lib.escapeShellArg "until=${cfg.docker.retention}"} || true
      docker network prune --force --filter ${lib.escapeShellArg "until=${cfg.docker.retention}"} || true

      ${lib.optionalString cfg.docker.pruneVolumes ''
        log "pruning unused Docker volumes"
        docker volume prune --force || true
      ''}

      log "docker disk usage after cleanup"
      docker system df || true
    '';
  };
in {
  options.dotfiles.rustDevCache = {
    enable = lib.mkEnableOption "shared Rust compilation cache and dev cache cleanup jobs";

    sccache = {
      cacheSize = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "50G";
        description = ''
          Maximum local sccache size. sccache applies this limit as an LRU cache
          while compiling, so it can replace duplicated per-project Cargo target
          artifacts without growing indefinitely.
        '';
      };

      directory = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "${config.home.homeDirectory}/.cache/sccache";
        defaultText = lib.literalExpression ''"\${config.home.homeDirectory}/.cache/sccache"'';
        description = "Directory used for the local sccache disk cache.";
      };
    };

    cleanup = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable the periodic launchd dev cache cleanup job on macOS.";
      };

      intervalSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 86400;
        description = ''
          Number of seconds between cleanup runs. On macOS, launchd does not wake
          a sleeping laptop to run the job.
        '';
      };
    };

    docker = {
      retention = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "336h";
        description = ''
          Docker prune age filter for containers, dangling images, networks, and
          builder cache. The value is passed to Docker as `until=<value>`.
        '';
      };

      builderMaxUsedSpace = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "30GB";
        description = ''
          Storage budget passed to `docker builder prune --max-used-space`. This
          keeps recent build cache around for active projects while still
          trimming old OrbStack/Docker build artifacts.
        '';
      };

      pruneVolumes = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Also prune unused Docker volumes. Disabled by default because volumes
          often contain local database or queue state for stopped dev stacks.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.cleanup.enable || pkgs.stdenv.isDarwin;
        message = "dotfiles.rustDevCache.cleanup.enable is currently supported only on Darwin via launchd.";
      }
    ];

    home.packages = [
      pkgs.docker-client
      pkgs.sccache
    ];

    home.sessionVariables = {
      RUSTC_WRAPPER = lib.getExe pkgs.sccache;
      SCCACHE_DIR = cfg.sccache.directory;
      SCCACHE_CACHE_SIZE = cfg.sccache.cacheSize;
    };

    home.file.".cargo/config.toml".text = ''
      [build]
      rustc-wrapper = "${lib.getExe pkgs.sccache}"

      [env]
      SCCACHE_DIR = "${cfg.sccache.directory}"
      SCCACHE_CACHE_SIZE = "${cfg.sccache.cacheSize}"
    '';

    launchd.agents.sccache-server = lib.mkIf pkgs.stdenv.isDarwin {
      enable = true;
      config = {
        ProgramArguments = [
          (lib.getExe serverScript)
        ];
        RunAtLoad = true;
        KeepAlive = true;
        ProcessType = "Background";
        LowPriorityIO = true;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/sccache-server.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/sccache-server.log";
      };
    };

    launchd.agents.dev-cache-cleanup = lib.mkIf (cfg.cleanup.enable && pkgs.stdenv.isDarwin) {
      enable = true;
      config = {
        ProgramArguments = [
          (lib.getExe cleanupScript)
        ];
        StartInterval = cfg.cleanup.intervalSeconds;
        ProcessType = "Background";
        LowPriorityIO = true;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/dev-cache-cleanup.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/dev-cache-cleanup.log";
      };
    };
  };
}
