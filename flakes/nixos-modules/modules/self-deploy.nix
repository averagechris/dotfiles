{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.selfDeploy;
  hostName =
    if cfg.hostName != null
    then cfg.hostName
    else config.networking.hostName;
  serviceName =
    if cfg.serviceName != null
    then cfg.serviceName
    else "dotfiles-${hostName}-self-deploy";
  attr =
    if cfg.attr != null
    then cfg.attr
    else "nixosConfigurations.${hostName}.config.system.build.toplevel";
  timerCfg = cfg.timer;
  selfDeploy = pkgs.writeShellApplication {
    name = serviceName;
    runtimeInputs = with pkgs; [
      coreutils
      git
      jq
      nix
      systemd
      util-linux
    ];
    text = ''
      set -euo pipefail

      state_dir=${lib.escapeShellArg cfg.stateDir}
      lock_file="$state_dir/deploy.lock"
      last_success_rev_file="$state_dir/last-success-rev"
      last_attempt_rev_file="$state_dir/last-attempt-rev"
      last_failure_rev_file="$state_dir/last-failure-rev"
      flake_ref=${lib.escapeShellArg cfg.flakeRef}
      attr=${lib.escapeShellArg attr}

      mkdir -p "$state_dir"

      exec 9>"$lock_file"
      if ! flock -n 9; then
        echo "Another ${hostName} self-deploy run is already active; exiting."
        exit 0
      fi

      latest_rev=$(nix flake metadata --json "$flake_ref" | jq -r '.revision // .locked.rev // empty')
      if [ -z "$latest_rev" ]; then
        echo "Could not determine latest revision for $flake_ref" >&2
        exit 1
      fi

      if [ -f "$last_success_rev_file" ] && [ "$(cat "$last_success_rev_file")" = "$latest_rev" ]; then
        echo "${hostName} is already deployed at $latest_rev"
        exit 0
      fi

      printf '%s\n' "$latest_rev" >"$last_attempt_rev_file"

      previous_system=$(readlink -f /run/current-system)
      echo "Previous system: $previous_system"
      echo "Building ${hostName} from $flake_ref at $latest_rev"

      if ! new_system=$(nix build \
        --accept-flake-config \
        --no-link \
        --print-out-paths \
        --print-build-logs \
        "$flake_ref#$attr"); then
        echo "Build failed for $latest_rev" >&2
        printf '%s\n' "$latest_rev" >"$last_failure_rev_file"
        exit 1
      fi

      echo "New system: $new_system"

      health_check() {
        local failed=0
        local required_units=(${lib.escapeShellArgs cfg.requiredSystemUnits})

        wait_for_unit() {
          local unit="$1"
          local deadline now
          deadline=$(($(date +%s) + ${toString cfg.unitCheckTimeoutSec}))

          while true; do
            if systemctl is-active --quiet "$unit"; then
              return 0
            fi

            now=$(date +%s)
            if [ "$now" -ge "$deadline" ]; then
              return 1
            fi

            sleep 5
          done
        }

        for unit in "''${required_units[@]}"; do
          if ! wait_for_unit "$unit"; then
            state=$(systemctl is-active "$unit" || true)
            echo "Required unit is not active after ${toString cfg.unitCheckTimeoutSec}s: $unit ($state)" >&2
            failed=1
          fi
        done

        ${lib.optionalString cfg.requireSystemRunning ''
        if ! systemctl is-system-running --quiet; then
          state=$(systemctl is-system-running || true)
          echo "System state after activation: $state" >&2
          systemctl --failed --no-pager >&2 || true
          failed=1
        fi
      ''}

        return "$failed"
      }

      echo "Activating $new_system"
      if ! "$new_system/bin/switch-to-configuration" switch; then
        echo "Activation failed; attempting rollback to $previous_system" >&2
        "$previous_system/bin/switch-to-configuration" switch || true
        printf '%s\n' "$latest_rev" >"$last_failure_rev_file"
        exit 1
      fi

      if health_check; then
        printf '%s\n' "$latest_rev" >"$last_success_rev_file"
        rm -f "$last_failure_rev_file"
        echo "Successfully deployed ${hostName} at $latest_rev"
        exit 0
      fi

      echo "Health check failed; rolling back to $previous_system" >&2
      if "$previous_system/bin/switch-to-configuration" switch && health_check; then
        echo "Rollback succeeded after failed deployment of $latest_rev" >&2
      else
        echo "Rollback failed or system is still unhealthy after rollback" >&2
      fi

      printf '%s\n' "$latest_rev" >"$last_failure_rev_file"
      exit 1
    '';
  };
in {
  options.dotfiles.selfDeploy = {
    enable = lib.mkEnableOption "pull-based self-deploy from the dotfiles main branch";

    hostName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Host name to build from the dotfiles flake. Defaults to networking.hostName.";
    };

    serviceName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "systemd service and timer name. Defaults to dotfiles-<host>-self-deploy.";
    };

    flakeRef = lib.mkOption {
      type = lib.types.str;
      default = "git+https://git.sr.ht/~averagechris/dotfiles?ref=main";
      description = "Flake reference to deploy from.";
    };

    attr = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Flake attribute to build. Defaults to the host's NixOS toplevel.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/dotfiles-${hostName}-self-deploy";
      description = "Directory for deployment lock and last-attempt/success/failure revision state.";
    };

    requiredSystemUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["sshd.service" "tailscaled.service" "nix-daemon.service"];
      description = "System units that must be active after activation and after rollback.";
    };

    requireSystemRunning = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Require systemctl is-system-running --quiet to pass after activation.";
    };

    unitCheckTimeoutSec = lib.mkOption {
      type = lib.types.ints.positive;
      default = 120;
      description = "Seconds to wait for each required system unit to become active before rollback.";
    };

    timeoutStartSec = lib.mkOption {
      type = lib.types.str;
      default = "4h";
      description = "Maximum time systemd allows for a build, activation, health check, and possible rollback.";
    };

    timer = {
      onBootSec = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "1h";
        description = "Delay after boot before the first self-deploy attempt.";
      };

      onUnitActiveSec = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "6h";
        description = "Delay after each run before the next self-deploy attempt.";
      };

      onCalendar = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional calendar expression for self-deploy attempts.";
      };

      persistent = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether missed timer runs catch up after downtime.";
      };

      randomizedDelaySec = lib.mkOption {
        type = lib.types.str;
        default = "30m";
        description = "Random delay to stagger hosts and give thorny time to warm build results.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0755 root root - -"
    ];

    systemd.services.${serviceName} = {
      description = "Pull and activate the latest ${hostName} system from dotfiles main";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe selfDeploy;
        TimeoutStartSec = cfg.timeoutStartSec;
        Nice = 10;
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 6;
      };
    };

    systemd.timers.${serviceName} = {
      description = "Regularly self-deploy ${hostName} from dotfiles main";
      wantedBy = ["timers.target"];
      timerConfig =
        {
          Persistent = timerCfg.persistent;
          RandomizedDelaySec = timerCfg.randomizedDelaySec;
          Unit = "${serviceName}.service";
        }
        // lib.optionalAttrs (timerCfg.onBootSec != null) {
          OnBootSec = timerCfg.onBootSec;
        }
        // lib.optionalAttrs (timerCfg.onUnitActiveSec != null) {
          OnUnitActiveSec = timerCfg.onUnitActiveSec;
        }
        // lib.optionalAttrs (timerCfg.onCalendar != null) {
          OnCalendar = timerCfg.onCalendar;
        };
    };
  };
}
