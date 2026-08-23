{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.opencode.sessionCleanup;
  stateDir = "${config.home.homeDirectory}/.local/state/opencode-session-cleanup";
  cleanupScript = pkgs.writeShellApplication {
    name = "opencode-session-cleanup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.python3
      config.programs.opencode.package
    ];
    text = ''
            set -uo pipefail

            log() {
              printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
            }

            # launchd can start this while an interactive OpenCode or ctx process is
            # using the database. Deletion is deliberately deferred in that case.
            self_pid=$$
            active=$(
              /bin/ps -ww -axo pid=,ucomm=,args= | /usr/bin/awk -v self="$self_pid" '
                $1 != self && ($2 ~ /(^|\/)opencode([.]|$)/ || $2 == "ctx" || $3 ~ /(^|\/)opencode([.]|$)/ || $3 == "ctx") { print $1 "/" $2 }
              '
            ) || {
              log "could not inspect processes; deferring"
              exit 75
            }
            if [ -n "$active" ]; then
              log "OpenCode/ctx is active ($active); deferring"
              exit 75
            fi

            cpu_count=$(/usr/sbin/sysctl -n hw.logicalcpu 2>/dev/null || true)
            load_one=$(/usr/sbin/sysctl -n vm.loadavg 2>/dev/null | /usr/bin/awk '{print $2}') || true
            if ! [[ "$cpu_count" =~ ^[1-9][0-9]*$ ]] || ! [[ "$load_one" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
              log "CPU headroom could not be inspected; deferring"
              exit 75
            fi
            if ! /usr/bin/awk -v load="$load_one" -v cpus="$cpu_count" \
              'BEGIN { exit !((load * 100) < (cpus * ${toString cfg.maxLoadPercent})) }'; then
              log "load average $load_one is too high for $cpu_count CPUs; deferring"
              exit 75
            fi

            today=$(date '+%Y-%m-%d')
            weekday=$(date '+%u')
            case "$weekday" in
              1|2|3|4|5) ;;
              *) log "weekend; deferring"; exit 0 ;;
            esac

            mkdir -p ${lib.escapeShellArg stateDir}
            lock_file=${lib.escapeShellArg stateDir}/lock
            if ! /usr/bin/shlock -f "$lock_file" -p $$; then
              log "another cleanup is active; deferring"
              exit 75
            fi
            release_lock() {
              lock_pid=$(cat "$lock_file" 2>/dev/null || true)
              [ "$lock_pid" = "$$" ] && rm -f "$lock_file"
            }
            trap release_lock EXIT

            stamp=${lib.escapeShellArg stateDir}/last-run
            if [ -f "$stamp" ] && [ "$(cat "$stamp" 2>/dev/null || true)" = "$today" ]; then
              exit 0
            fi

      db="$HOME/.local/share/opencode/opencode.db"
            if [ ! -r "$db" ]; then
              log "database not found: $db"
              exit 0
            fi

            # Read the database through SQLite's read-only URI, then perform each
            # mutation through OpenCode's supported one-session deletion command.
            # Always leave at least minSessions newest sessions behind, including when
            # every session is older than maxAgeDays.
            candidates=$(python3 - "$db" ${toString cfg.maxAgeDays} ${toString cfg.minSessions} <<'PY'
      import sqlite3
      import sys
      import time

      path, age_days, minimum = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
      uri = "file:" + path + "?mode=ro"
      with sqlite3.connect(uri, uri=True) as db:
          rows = db.execute(
              "SELECT id, time_updated FROM session ORDER BY time_updated ASC, id ASC"
          ).fetchall()

      cutoff = int((time.time() - age_days * 86400) * 1000)
      old = [session_id for session_id, updated in rows if updated < cutoff]
      for session_id in old[:max(0, len(rows) - minimum)]:
          print(session_id)
      PY
            ) || {
              log "could not read OpenCode database; deferring"
              exit 75
            }

            if [ -z "$candidates" ]; then
              log "no sessions older than ${toString cfg.maxAgeDays} days require deletion"
        printf '%s\n' "$today" > "$stamp"
              exit 0
            fi

            deleted=0
            failed=0
            while IFS= read -r session_id; do
              [ -n "$session_id" ] || continue
              if opencode session delete "$session_id"; then
                deleted=$((deleted + 1))
              else
                failed=$((failed + 1))
                log "failed to delete session $session_id; continuing"
              fi
            done <<< "$candidates"

            # A failed deletion is not a successful maintenance run: retry next hour
            # without stamping the day, while a successful/no-op run is daily gated.
            if [ "$failed" -gt 0 ]; then
              log "deleted $deleted session(s), $failed failed; retrying later"
              exit 75
            fi
            log "deleted $deleted session(s); retaining at least ${toString cfg.minSessions}"
      printf '%s\n' "$today" > "$stamp"
    '';
  };
  calendar =
    lib.concatMap (
      weekday:
        map (hour: {
          Weekday = weekday;
          Hour = hour;
          Minute = 0;
        }) (lib.range 0 23)
    )
    cfg.weekdays;
in {
  options.dotfiles.opencode.sessionCleanup = {
    enable = lib.mkEnableOption "load-aware weekday OpenCode session cleanup";
    maxAgeDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 45;
      description = "Delete sessions older than this many days.";
    };
    minSessions = lib.mkOption {
      type = lib.types.ints.positive;
      default = 25;
      description = "Always retain at least this many newest sessions.";
    };
    maxLoadPercent = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 60;
      description = "Defer cleanup when one-minute load exceeds this CPU percentage.";
    };
    weekdays = lib.mkOption {
      type = lib.types.listOf (lib.types.ints.between 1 7);
      default = [1 2 3 4 5];
      description = "launchd weekdays on which cleanup is checked.";
    };
  };

  config = lib.mkIf (config.programs.opencode.enable && cfg.enable && pkgs.stdenv.isDarwin) {
    home.packages = [cleanupScript];
    launchd.agents.opencode-session-cleanup = {
      enable = true;
      config = {
        ProgramArguments = [(lib.getExe cleanupScript)];
        StartCalendarInterval = calendar;
        ProcessType = "Background";
        LowPriorityIO = true;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/opencode-session-cleanup.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/opencode-session-cleanup.log";
      };
    };
  };
}
