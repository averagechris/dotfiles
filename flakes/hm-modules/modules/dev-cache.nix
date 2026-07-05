{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.devCache;

  # Run the sccache server supervised in the foreground with a clean service
  # environment. Without this, the server is auto-started by whichever compile
  # happens first and inherits that process's environment; on macOS a server
  # started inside a nix shell (where DEVELOPER_DIR points at the nix Apple
  # SDK) poisons every later C compile through /usr/bin/cc's xcselect shim with
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
    runtimeInputs =
      [
        pkgs.cargo-sweep
        pkgs.coreutils
        pkgs.findutils
        pkgs.nix
        pkgs.sccache
      ]
      ++ lib.optional cfg.docker.enable pkgs.docker-client;
    text = ''
      set -uo pipefail

      log() {
        printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
      }

      available_kib() {
        df -Pk "$1" | tail -n 1 | tr -s ' ' | cut -d ' ' -f 4
      }

      root_available_kib() {
        local available
        available=$(available_kib / 2>/dev/null || printf '0')
        if [ -z "$available" ]; then
          available=0
        fi
        printf '%s\n' "$available"
      }

      root_available_gib() {
        local available
        available=$(root_available_kib)
        printf '%s\n' "$((available / 1024 / 1024))"
      }

      root_is_low_disk() {
        local available
        available=$(root_available_kib)
        [ "$available" -lt ${toString (cfg.cleanup.lowDisk.minFreeGiB * 1024 * 1024)} ]
      }

      pressure_mode=0
      case "''${1:-}" in
        --pressure)
          pressure_mode=1
          ;;
        "")
          ;;
        *)
          log "unknown argument: $1"
          exit 2
          ;;
      esac

      lock_dir="''${XDG_RUNTIME_DIR:-''${TMPDIR:-/tmp}}/dotfiles-dev-cache-cleanup.lock"
      if mkdir "$lock_dir" 2>/dev/null; then
        cleanup_lock() {
          rmdir "$lock_dir" 2>/dev/null || true
        }
        trap cleanup_lock EXIT
      else
        log "another dev-cache-cleanup instance is running; exiting"
        exit 0
      fi

      export SCCACHE_DIR=${lib.escapeShellArg cfg.sccache.directory}
      export SCCACHE_CACHE_SIZE=${lib.escapeShellArg cfg.sccache.cacheSize}

      log "root filesystem usage before cleanup"
      df -h / || true

      log "sccache stats (server is managed by the supervised sccache-server service)"
      sccache --show-stats || true

      ${lib.optionalString cfg.nixGc.enable ''
        log "nix store usage before garbage collection"
        df -h /nix || true

        # Running unprivileged, this deletes only *user* profile generations
        # (home-manager, nix profile) older than the retention window, then
        # garbage-collects unreferenced store paths through the daemon.
        # Root-owned darwin system profile generations under
        # /nix/var/nix/profiles are never deleted by an unprivileged run, and
        # every store path referenced by any remaining generation is a GC
        # root, so the current and previous darwin system generations always
        # survive this job.
        log "collecting nix garbage (user profile generations older than ${toString cfg.nixGc.olderThanDays} days)"
        nix-collect-garbage --delete-older-than ${lib.escapeShellArg "${toString cfg.nixGc.olderThanDays}d"} || true

        log "nix store usage after garbage collection"
        df -h /nix || true
      ''}

      ${lib.optionalString (cfg.nixGc.rootGcReminder.enable && pkgs.stdenv.isDarwin) ''
        # Unprivileged GC never removes root-owned darwin system generations,
        # so remind about the manual root-level cleanup once they pile up. The
        # suggested command keeps the most recent generations, so the current
        # and immediately previous darwin profiles always survive.
        system_generations=$(find /nix/var/nix/profiles -maxdepth 1 -name 'system-*-link' 2>/dev/null | wc -l | tr -d ' ')
        log "darwin system profile has $system_generations root-owned generations (unprivileged GC cannot remove them)"
        if [ "$system_generations" -gt ${toString cfg.nixGc.rootGcReminder.maxSystemGenerations} ]; then
          log "reminder: run the manual root-level GC, keeping recent rollback targets:"
          log "  sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations +5 && sudo nix-collect-garbage"
          /usr/bin/osascript -e "display notification \"$system_generations darwin system generations accumulated. Run the root GC cleanup (command in dev-cache-cleanup.log).\" with title \"Nix maintenance\"" || true
        fi
      ''}

      ${lib.optionalString cfg.cargoSweep.enable ''
        log "sweeping cargo target artifacts untouched for ${toString cfg.cargoSweep.staleDays} days"
        ${lib.concatMapStringsSep "\n" (root: ''
            if [ -d ${lib.escapeShellArg root} ]; then
              cargo-sweep sweep --recursive --time ${toString cfg.cargoSweep.staleDays} ${lib.escapeShellArg root} || true
            else
              log "cargo sweep root ${lib.escapeShellArg root} does not exist; skipping"
            fi
          '')
          cfg.cargoSweep.roots}
      ''}

      ${lib.optionalString cfg.docker.enable ''
        if ! docker info >/dev/null 2>&1; then
          log "docker daemon is unavailable; skipping Docker/OrbStack cleanup"
        else
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
        fi
      ''}

      ${lib.optionalString cfg.cleanup.lowDisk.enable ''
        if [ "$pressure_mode" -eq 1 ] || root_is_low_disk; then
          log "low-disk pressure cleanup triggered: $(root_available_gib) GiB free on /; threshold is ${toString cfg.cleanup.lowDisk.minFreeGiB} GiB"
          ${lib.optionalString (cfg.cleanup.lowDisk.notify && pkgs.stdenv.isDarwin) ''
          /usr/bin/osascript -e "display notification \"Low disk cleanup started ($(root_available_gib) GiB free; threshold ${toString cfg.cleanup.lowDisk.minFreeGiB} GiB).\" with title \"Dev cache cleanup\"" || true
        ''}

          ${lib.optionalString cfg.nixGc.enable ''
          log "low-disk: aggressively collecting nix garbage"
          ${lib.optionalString cfg.cleanup.lowDisk.deleteOldUserGenerations ''
            log "low-disk: deleting all old user profile generations before store GC"
            nix-collect-garbage -d || true
          ''}
          log "low-disk: collecting unreferenced nix store paths"
          nix store gc || true
          log "low-disk: nix store usage after aggressive garbage collection"
          df -h /nix || true
        ''}

          ${lib.optionalString cfg.cargoSweep.enable ''
          log "low-disk: sweeping cargo target artifacts untouched for ${toString cfg.cleanup.lowDisk.cargoSweepStaleDays} days"
          ${lib.concatMapStringsSep "\n" (root: ''
              if [ -d ${lib.escapeShellArg root} ]; then
                cargo-sweep sweep --recursive --time ${toString cfg.cleanup.lowDisk.cargoSweepStaleDays} ${lib.escapeShellArg root} || true
              else
                log "cargo sweep root ${lib.escapeShellArg root} does not exist; skipping"
              fi
            '')
            cfg.cargoSweep.roots}
        ''}

          ${lib.optionalString cfg.docker.enable ''
          if ! docker info >/dev/null 2>&1; then
            log "low-disk: docker daemon is unavailable; skipping Docker/OrbStack cleanup"
          else
            log "low-disk: pruning Docker/OrbStack builder cache older than ${cfg.cleanup.lowDisk.dockerRetention} with max-used-space ${cfg.cleanup.lowDisk.dockerBuilderMaxUsedSpace}"
            docker builder prune \
              --all \
              --force \
              --filter ${lib.escapeShellArg "until=${cfg.cleanup.lowDisk.dockerRetention}"} \
              --max-used-space ${lib.escapeShellArg cfg.cleanup.lowDisk.dockerBuilderMaxUsedSpace} || true

            log "low-disk: pruning stopped containers, dangling images, and unused networks older than ${cfg.cleanup.lowDisk.dockerRetention}"
            docker container prune --force --filter ${lib.escapeShellArg "until=${cfg.cleanup.lowDisk.dockerRetention}"} || true
            docker image prune --force --filter ${lib.escapeShellArg "until=${cfg.cleanup.lowDisk.dockerRetention}"} || true
            docker network prune --force --filter ${lib.escapeShellArg "until=${cfg.cleanup.lowDisk.dockerRetention}"} || true

            ${lib.optionalString cfg.docker.pruneVolumes ''
            log "low-disk: pruning unused Docker volumes"
            docker volume prune --force || true
          ''}

            log "low-disk: docker disk usage after pressure cleanup"
            docker system df || true
          fi
        ''}
        else
          log "low-disk pressure cleanup not needed: $(root_available_gib) GiB free on /; threshold is ${toString cfg.cleanup.lowDisk.minFreeGiB} GiB"
        fi
      ''}

      log "root filesystem usage after cleanup"
      df -h / || true
    '';
  };

  lowDiskCleanupScript = pkgs.writeShellApplication {
    name = "dotfiles-dev-cache-low-disk-cleanup";
    runtimeInputs = [
      pkgs.coreutils
    ];
    text = ''
      set -uo pipefail

      available_kib() {
        df -Pk / | tail -n 1 | tr -s ' ' | cut -d ' ' -f 4
      }

      available=$(available_kib 2>/dev/null || printf '0')
      if [ -z "$available" ]; then
        available=0
      fi

      threshold=${toString (cfg.cleanup.lowDisk.minFreeGiB * 1024 * 1024)}
      if [ "$available" -lt "$threshold" ]; then
        printf '[%s] low disk detected: %s GiB free on /; threshold is ${toString cfg.cleanup.lowDisk.minFreeGiB} GiB\n' \
          "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
          "$((available / 1024 / 1024))"
        exec ${lib.getExe cleanupScript}
      fi
    '';
  };
in {
  options.dotfiles.devCache = {
    enable = lib.mkEnableOption "dev cache management: shared Rust compilation cache and periodic nix/cargo/docker cleanup jobs";

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
        description = ''
          Enable the periodic dev cache cleanup job (launchd on macOS, a
          systemd user timer on Linux).
        '';
      };

      intervalSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 86400;
        description = ''
          Number of seconds between cleanup runs. On macOS, launchd does not wake
          a sleeping laptop to run the job.
        '';
      };

      lowDisk = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Enable a lightweight low-disk monitor that checks the root filesystem
            more frequently than the full periodic cleanup. When free space drops
            below <literal>minFreeGiB</literal>, it runs the cleanup job, which
            can escalate to the low-disk pressure cleanup phase.
          '';
        };

        checkIntervalSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 1800;
          description = ''
            Number of seconds between low-disk checks. The check is intentionally
            cheap and only starts the full cleanup when the root filesystem is
            below <literal>minFreeGiB</literal>.
          '';
        };

        minFreeGiB = lib.mkOption {
          type = lib.types.ints.positive;
          default = 30;
          description = ''
            Minimum desired free space on the root filesystem. If a cleanup run
            ends below this threshold, the low-disk pressure phase runs.
          '';
        };

        deleteOldUserGenerations = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            During low-disk pressure cleanup, run
            <literal>nix-collect-garbage -d</literal> before
            <literal>nix store gc</literal>. This removes old user profile
            generations but still cannot remove root-owned darwin system
            generations from an unprivileged job.
          '';
        };

        cargoSweepStaleDays = lib.mkOption {
          type = lib.types.ints.positive;
          default = 1;
          description = ''
            More aggressive Cargo artifact staleness window used only during the
            low-disk pressure cleanup phase.
          '';
        };

        dockerRetention = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "24h";
          description = ''
            More aggressive Docker prune age filter used only during the
            low-disk pressure cleanup phase.
          '';
        };

        dockerBuilderMaxUsedSpace = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "10GB";
          description = ''
            Tighter Docker builder cache budget used only during the low-disk
            pressure cleanup phase.
          '';
        };

        notify = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            On macOS, post a notification when the low-disk pressure cleanup
            phase starts.
          '';
        };
      };
    };

    nixGc = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Run `nix-collect-garbage --delete-older-than <olderThanDays>d` as part
          of the periodic cleanup job. Unprivileged runs only delete user
          profile generations (home-manager, `nix profile`); root-owned darwin
          system generations are never removed, so the current and previous
          system profiles always remain rollback targets.
        '';
      };

      olderThanDays = lib.mkOption {
        type = lib.types.ints.positive;
        default = 7;
        description = ''
          Retention window in days for user profile generations before nix
          garbage collection.
        '';
      };

      rootGcReminder = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            On macOS, post a notification from the cleanup job when root-owned
            darwin system generations accumulate beyond
            <literal>maxSystemGenerations</literal>, reminding that the manual
            root-level GC is due. The suggested command keeps the most recent
            generations so the previous darwin profile is never lost.
          '';
        };

        maxSystemGenerations = lib.mkOption {
          type = lib.types.ints.positive;
          default = 10;
          description = ''
            Notify when the count of darwin system profile generations exceeds
            this threshold.
          '';
        };
      };
    };

    cargoSweep = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Run `cargo-sweep` in the periodic cleanup job to delete stale Cargo
          target artifacts (per-file, based on last use) under
          <literal>roots</literal>. Removed artifacts are rebuilt on demand and
          mostly restored from sccache.
        '';
      };

      staleDays = lib.mkOption {
        type = lib.types.ints.positive;
        default = 7;
        description = ''
          Age in days passed to `cargo-sweep sweep --time`; target artifacts
          not used within this window are deleted. Worst case, swept artifacts
          are recompiled (mostly from sccache) on the next build.
        '';
      };

      roots = lib.mkOption {
        type = lib.types.listOf lib.types.nonEmptyStr;
        default = ["${config.home.homeDirectory}/projects"];
        defaultText = lib.literalExpression ''["''${config.home.homeDirectory}/projects"]'';
        description = ''
          Directories scanned recursively by cargo-sweep for Cargo target
          directories.
        '';
      };
    };

    docker = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Include the Docker/OrbStack pruning phase in the cleanup job and
          install the Docker CLI. When enabled on a host without a running
          Docker-compatible daemon, the phase is skipped gracefully at runtime.
        '';
      };

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
    home.packages =
      [
        cleanupScript
        pkgs.sccache
      ]
      ++ lib.optional cfg.cleanup.lowDisk.enable lowDiskCleanupScript
      ++ lib.optional cfg.docker.enable pkgs.docker-client;

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

    launchd.agents.dev-cache-low-disk-cleanup = lib.mkIf (cfg.cleanup.enable && cfg.cleanup.lowDisk.enable && pkgs.stdenv.isDarwin) {
      enable = true;
      config = {
        ProgramArguments = [
          (lib.getExe lowDiskCleanupScript)
        ];
        StartInterval = cfg.cleanup.lowDisk.checkIntervalSeconds;
        ProcessType = "Background";
        LowPriorityIO = true;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/dev-cache-cleanup.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/dev-cache-cleanup.log";
      };
    };

    systemd.user.services.sccache-server = lib.mkIf pkgs.stdenv.isLinux {
      Unit = {
        Description = "Supervised sccache server";
      };
      Service = {
        ExecStart = lib.getExe serverScript;
        Restart = "always";
        RestartSec = 5;
        Nice = 10;
        IOSchedulingClass = "idle";
      };
      Install = {
        WantedBy = ["default.target"];
      };
    };

    systemd.user.services.dev-cache-cleanup = lib.mkIf (cfg.cleanup.enable && pkgs.stdenv.isLinux) {
      Unit = {
        Description = "Dev cache cleanup (nix GC, cargo sweep, docker prune)";
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe cleanupScript;
        Nice = 10;
        IOSchedulingClass = "idle";
      };
    };

    systemd.user.services.dev-cache-low-disk-cleanup = lib.mkIf (cfg.cleanup.enable && cfg.cleanup.lowDisk.enable && pkgs.stdenv.isLinux) {
      Unit = {
        Description = "Dev cache low-disk cleanup check";
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe lowDiskCleanupScript;
        Nice = 10;
        IOSchedulingClass = "idle";
      };
    };

    systemd.user.timers.dev-cache-cleanup = lib.mkIf (cfg.cleanup.enable && pkgs.stdenv.isLinux) {
      Unit = {
        Description = "Periodic dev cache cleanup";
      };
      Timer = {
        OnStartupSec = "15min";
        OnUnitActiveSec = "${toString cfg.cleanup.intervalSeconds}s";
      };
      Install = {
        WantedBy = ["timers.target"];
      };
    };

    systemd.user.timers.dev-cache-low-disk-cleanup = lib.mkIf (cfg.cleanup.enable && cfg.cleanup.lowDisk.enable && pkgs.stdenv.isLinux) {
      Unit = {
        Description = "Periodic dev cache low-disk cleanup check";
      };
      Timer = {
        OnStartupSec = "5min";
        OnUnitActiveSec = "${toString cfg.cleanup.lowDisk.checkIntervalSeconds}s";
      };
      Install = {
        WantedBy = ["timers.target"];
      };
    };
  };
}
