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

            # Nix materializes this source in the store.
            # shellcheck disable=SC1091
            source ${./service-guard.sh}

            log() {
              printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
            }

            # The V2 background service is normally always present, so an OpenCode
            # process is no longer evidence that a session is active. ctx still reads
            # session storage directly and is kept out of the cleanup window.
            self_pid=$$
            active=$(
              /bin/ps -ww -axo pid=,ucomm=,args= | /usr/bin/awk -v self="$self_pid" '
                $1 != self && ($2 == "ctx" || $3 == "ctx") { print $1 "/" $2 }
              '
            ) || {
              log "could not inspect processes; deferring"
              exit 75
            }
            if [ -n "$active" ]; then
              log "ctx is active ($active); deferring"
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
              [ -z "''${sessions_file:-}" ] || rm -f "$sessions_file"
            }
            trap release_lock EXIT

            stamp=${lib.escapeShellArg stateDir}/last-run
            if [ -f "$stamp" ] && [ "$(cat "$stamp" 2>/dev/null || true)" = "$today" ]; then
              exit 0
            fi

            # Query and mutate through the same managed V2 service. This avoids
            # selecting a channel- or service-configured database different from the
            # one used by `session delete`.
            if ! require_running_opencode_service; then
              log "managed OpenCode service is stopped or unavailable; deferring"
              exit 75
            fi
            has_active_sessions() {
              active_sessions=$(opencode api session.active) || return 1
              python3 -c '
      import json, sys
      payload = json.load(sys.stdin)
      data = payload["data"]
      if not isinstance(data, dict):
          raise TypeError("session.active data is not an object")
      print("yes" if data else "no")
      ' <<< "$active_sessions"
            }
            active_state=$(has_active_sessions) || {
              log "could not inspect active OpenCode sessions; deferring"
              exit 75
            }
            if [ "$active_state" = yes ]; then
              log "OpenCode has an active session; deferring"
              exit 75
            fi

            sessions_file=$(mktemp ${lib.escapeShellArg stateDir}/sessions.XXXXXX)
            list_sessions() {
              : > "$sessions_file"
              cursor=
              seen_cursors='|'
              while true; do
                if [ -n "$cursor" ]; then
                  require_running_opencode_service || return 75
                  page=$(opencode api session.list --param limit=100000 --param order=desc --param cursor="$cursor") || return 1
                else
                  require_running_opencode_service || return 75
                  page=$(opencode api session.list --param limit=100000 --param order=desc) || return 1
                fi
                printf '%s\n' "$page" >> "$sessions_file"
                page_result=$(python3 -c '
      import json, sys
      payload = json.load(sys.stdin)
      rows = payload["data"]
      if not isinstance(rows, list):
          raise TypeError("session.list data is not a list")
      print((payload.get("cursor") or {}).get("next") or "")
      print(len(rows))
      ' <<< "$page") || return 1
                cursor=$(printf '%s\n' "$page_result" | /usr/bin/awk 'NR == 1')
                count=$(printf '%s\n' "$page_result" | /usr/bin/awk 'NR == 2')
                [ "$count" -gt 0 ] || break
                [ -n "$cursor" ] || break
                case "$seen_cursors" in
                  *"|$cursor|"*) return 1 ;;
                esac
                seen_cursors="$seen_cursors$cursor|"
              done
            }
            list_sessions || {
              log "could not list OpenCode sessions; deferring"
              exit 75
            }

            # A delete cascades to children. Select only maximal subtrees in which
            # every session is old and outside the globally protected newest set.
            select_candidates() {
              python3 - ${toString cfg.maxAgeDays} ${toString cfg.minSessions} "$sessions_file" <<'PY'
      import datetime
      import json
      import sys
      import time

      age_days, minimum = int(sys.argv[1]), int(sys.argv[2])
      rows = []
      with open(sys.argv[3], encoding="utf-8") as stream:
          for line in stream:
              payload = json.loads(line)
              rows.extend(payload["data"])
      if len({row["id"] for row in rows}) != len(rows):
          raise RuntimeError("duplicate session across pages")
      def millis(value):
          if isinstance(value, (int, float)):
              return value
          return datetime.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp() * 1000
      rows.sort(key=lambda row: (millis(row["time"]["updated"]), row["id"]), reverse=True)
      protected = {row["id"] for row in rows[:minimum]}
      cutoff = int((time.time() - age_days * 86400) * 1000)
      eligible = {row["id"] for row in rows if row["id"] not in protected and millis(row["time"]["updated"]) < cutoff}
      children = {row["id"]: [] for row in rows}
      parent = {}
      for row in rows:
          parent[row["id"]] = row.get("parentID")
          if row.get("parentID") in children:
              children[row["parentID"]].append(row["id"])
      state = {}
      def safe_subtree(session_id):
          if state.get(session_id) == 1:
              raise RuntimeError("cycle in session parent graph")
          if session_id in state:
              return state[session_id] == 2
          state[session_id] = 1
          safe = session_id in eligible and all(safe_subtree(child) for child in children[session_id])
          state[session_id] = 2 if safe else 3
          return safe
      safe = {row["id"] for row in rows if safe_subtree(row["id"])}
      for row in reversed(rows):
          session_id = row["id"]
          if session_id in safe and parent[session_id] not in safe:
              print(session_id)
      PY
            }
            candidates=$(select_candidates) || {
              log "could not select OpenCode sessions safely; deferring"
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
              # The list used for selection is only a snapshot. Recheck activity and
              # recompute the safe maximal roots immediately before each cascade so
              # a newly active/updated descendant cannot be deleted from stale data.
              if ! require_running_opencode_service; then
                log "managed OpenCode service stopped during cleanup; stopping"
                failed=$((failed + 1))
                break
              fi
              active_state=$(has_active_sessions) || {
                log "could not recheck active OpenCode sessions; stopping"
                failed=$((failed + 1))
                break
              }
              if [ "$active_state" = yes ]; then
                log "OpenCode became active; stopping"
                failed=$((failed + 1))
                break
              fi
              if ! require_running_opencode_service; then
                log "managed OpenCode service stopped during cleanup; stopping"
                failed=$((failed + 1))
                break
              fi
              if ! list_sessions; then
                log "could not refresh OpenCode sessions; stopping"
                failed=$((failed + 1))
                break
              fi
              refreshed=$(select_candidates) || {
                log "could not refresh deletion selection; stopping"
                failed=$((failed + 1))
                break
              }
              if ! printf '%s\n' "$refreshed" | /usr/bin/awk -v id="$session_id" '$0 == id { found=1 } END { exit !found }'; then
                log "session $session_id is no longer a safe deletion root; skipping"
                continue
              fi
              if ! require_running_opencode_service; then
                log "managed OpenCode service stopped during cleanup; stopping"
                failed=$((failed + 1))
                break
              fi
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
