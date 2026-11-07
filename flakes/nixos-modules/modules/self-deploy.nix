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

      metadata_json=$(nix flake metadata --json "$flake_ref")
      latest_rev=$(jq -r '(.revision | select(type == "string" and length > 0)) // .locked.rev // empty' <<<"$metadata_json")
      locked_flake_ref=$(jq -r '(.lockedUrl // .url // empty) | select(type == "string")' <<<"$metadata_json")
      if [[ ! "$latest_rev" =~ ^([0-9a-fA-F]{40}|[0-9a-fA-F]{64})$ ]]; then
        echo "Could not determine a valid locked revision for $flake_ref" >&2
        exit 1
      fi
      locked_rev=$(jq -r '.locked.rev // empty' <<<"$metadata_json")
      if [ -n "$locked_rev" ] && [ "$locked_rev" != "$latest_rev" ]; then
        echo "Flake metadata revision does not match its locked revision for $flake_ref" >&2
        exit 1
      fi
      if [ -z "$locked_flake_ref" ] || [[ "$locked_flake_ref" == *'#'* ]]; then
        echo "Could not determine a locked flake URL for $flake_ref" >&2
        exit 1
      fi
      locked_url_rev=$(jq -rn --arg url "$locked_flake_ref" --arg rev "$latest_rev" '
        $url | if startswith("github:") then
          (split("?")[0] | [scan("/([0-9a-fA-F]{40}|[0-9a-fA-F]{64})$")] | if length == 1 then .[0][0] else "" end)
        else
          ([scan("[?&]rev=([^&#]*)")] | if length == 1 and .[0][0] == $rev then .[0][0] else "" end)
        end
      ')
      if [ "$locked_url_rev" != "$latest_rev" ]; then
        echo "Locked flake URL is not pinned to the resolved revision for $flake_ref" >&2
        exit 1
      fi

      if [ -f "$last_success_rev_file" ] && [ "$(cat "$last_success_rev_file")" = "$latest_rev" ]; then
        echo "${hostName} is already deployed at $latest_rev"
        exit 0
      fi

      printf '%s\n' "$latest_rev" >"$last_attempt_rev_file"

      previous_system=$(readlink -f /run/current-system)
      if [ -z "$previous_system" ] || [ ! -x "$previous_system/bin/switch-to-configuration" ]; then
        echo "Current system closure is unavailable or invalid: $previous_system" >&2
        exit 1
      fi
      echo "Previous system: $previous_system"
      echo "Building ${hostName} from $flake_ref at $latest_rev"

      if ! new_system=$(nix build \
        --accept-flake-config \
        --no-link \
        --print-out-paths \
        --print-build-logs \
        "$locked_flake_ref#$attr"); then
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

      system_profile=/nix/var/nix/profiles/system
      restore_previous_system() {
        local check_health="$1"
        echo "Restoring system profile to $previous_system" >&2
        if ! nix-env --profile "$system_profile" --set "$previous_system"; then
          echo "Could not restore the system profile to $previous_system" >&2
          return 1
        fi
        if ! "$previous_system/bin/switch-to-configuration" switch; then
          echo "Could not reactivate previous system $previous_system" >&2
          return 1
        fi
        if [ "$check_health" = true ] && ! health_check; then
          echo "Previous system is still unhealthy after rollback" >&2
          return 1
        fi
        return 0
      }

      echo "Setting system profile to $new_system"
      if ! nix-env --profile "$system_profile" --set "$new_system"; then
        echo "Could not set system profile to $new_system; attempting rollback" >&2
        restore_previous_system false || true
        printf '%s\n' "$latest_rev" >"$last_failure_rev_file"
        exit 1
      fi

      echo "Activating $new_system"
      if ! "$new_system/bin/switch-to-configuration" switch; then
        echo "Activation failed; attempting rollback to $previous_system" >&2
        restore_previous_system false || true
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
      if restore_previous_system true; then
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
      default = "git+https://github.com/averagechris/dotfiles?ref=main";
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
      # Activation must not kill the process performing the deployment.
      restartIfChanged = false;
      stopIfChanged = false;
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
