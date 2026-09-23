{
  config,
  lib,
  pkgs,
  ...
}: let
  user = "chris";
  stateDir = "/Users/${user}/.local/state/dotfiles-self-update";
  repoDir = "${stateDir}/repo";
  outLink = "${stateDir}/result";
  markerPath = "${stateDir}/pending-activation";
  logPath = "/Users/${user}/Library/Logs/dotfiles-self-update.log";
  flakeUrl = "https://github.com/averagechris/dotfiles";
  branch = "main";
  # Attempt at most one update per day, but wake cheaply every five minutes so
  # a missed or busy window can use the next period with CPU headroom.
  minSecondsBetweenRuns = 23 * 60 * 60;
  # How long a pending-activation marker may go unconfirmed before the
  # reconciler declares the activation failed.
  markerStaleSeconds = 2 * 60 * 60;
  macosNixMaintenance = import ../../base-lib/macos-nix-maintenance.nix {
    inherit pkgs user;
  };

  notifyFn = ''
    notify() {
      local title="$1"
      local message="$2"
      /usr/bin/osascript - "$title" "$message" <<'APPLESCRIPT' || true
    on run argv
    display notification (item 2 of argv) with title (item 1 of argv)
    end run
    APPLESCRIPT
    }
  '';

  askpass = pkgs.writeShellApplication {
    name = "dotfiles-self-update-askpass";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      set -euo pipefail

      prompt=''${1:-dotfiles self-update needs your macOS password to activate the new system.}
      /usr/bin/osascript - "$prompt" <<'APPLESCRIPT'
      on run argv
      set dialogResult to display dialog (item 1 of argv) default answer "" with hidden answer with icon caution buttons {"Cancel", "OK"} default button "OK"
      text returned of dialogResult
      end run
      APPLESCRIPT
    '';
  };

  # Reconciles a pending-activation marker. The self-update script writes the
  # marker just before activation; when an update changes the self-update
  # agent itself, activation restarts that agent and kills the running script
  # before it can report success. This script closes that gap: it is run by
  # the notify agent (reloaded in exactly that scenario) and at the start of
  # every self-update run.
  reconcile = pkgs.writeShellApplication {
    name = "dotfiles-self-update-reconcile";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      set -euo pipefail

      marker=${lib.escapeShellArg markerPath}
      marker_stale_seconds=${toString markerStaleSeconds}

      ${notifyFn}

      [ -f "$marker" ] || exit 0
      read -r target rev stamp <"$marker" || exit 0
      if [[ "$stamp" =~ ^(0|[1-9][0-9]{0,10})$ ]]; then
        stamp=$((10#$stamp))
      else
        stamp=0
      fi

      # --wait polls while an activation may still be in flight;
      # /run/current-system is flipped at the very end of activation.
      wait_seconds=0
      if [ "''${1:-}" = "--wait" ]; then
        wait_seconds=600
      fi
      deadline=$(($(date +%s) + wait_seconds))

      while :; do
        current=$(readlink /run/current-system 2>/dev/null || true)
        if [ "$current" = "$target" ]; then
          rm -f "$marker"
          echo "Confirmed self-update activation of $target (rev $rev)."
          notify "dotfiles self-update" "suremac was updated successfully."
          exit 0
        fi
        if [ "$(date +%s)" -ge "$deadline" ]; then
          break
        fi
        sleep 5
      done

      if [ $(($(date +%s) - stamp)) -gt "$marker_stale_seconds" ]; then
        rm -f "$marker"
        echo "Pending self-update activation of $target (rev $rev) never became current; giving up."
        notify "dotfiles self-update failed" "Activation did not complete. See ${logPath}."
        exit 0
      fi

      echo "Pending self-update activation of $target is not current yet; will re-check later."
    '';
  };

  selfUpdate = pkgs.writeShellApplication {
    name = "dotfiles-suremac-self-update";
    runtimeInputs = with pkgs; [coreutils gitMinimal nix];
    text = ''
      set -euo pipefail

      state_dir=${lib.escapeShellArg stateDir}
      repo_dir=${lib.escapeShellArg repoDir}
      out_link=${lib.escapeShellArg outLink}
      marker=${lib.escapeShellArg markerPath}
      flake_url=${lib.escapeShellArg flakeUrl}
      branch=${lib.escapeShellArg branch}
      last_run_file="$state_dir/last-run"
      min_seconds_between_runs=${toString minSecondsBetweenRuns}
      force=0

      case "''${1:-}" in
        --force)
          force=1
          ;;
        "")
          ;;
        *)
          echo "usage: dotfiles-suremac-self-update [--force]" >&2
          exit 2
          ;;
      esac

      ${notifyFn}

      mkdir -p "$state_dir"

      # Settle any marker left behind by a previous run that was restarted
      # mid-activation (see the reconcile script and notify agent).
      ${lib.getExe reconcile}

      # Unless forced, skip when the last attempt was recent. The agent wakes
      # frequently, but this keeps the expensive cadence at roughly once per
      # day and lets a missed or busy window use the next headroom opportunity.
      if [ "$force" -eq 0 ] && [ -f "$last_run_file" ]; then
        last_run=$(cat "$last_run_file" 2>/dev/null || true)
        # A corrupted stamp must not wedge the job with a bash arithmetic error.
        if [[ "$last_run" =~ ^(0|[1-9][0-9]{0,10})$ ]]; then
          last_run=$((10#$last_run))
        else
          last_run=0
        fi
        now=$(date +%s)
        elapsed=$((now - last_run))
        if [ "$elapsed" -lt 0 ]; then
          elapsed=$min_seconds_between_runs
        fi
        if [ "$elapsed" -lt "$min_seconds_between_runs" ]; then
          exit 0
        fi
      fi

      # StartInterval also fires after sleep. Do not turn that catch-up wake
      # into an immediate build while the user or development tools are busy;
      # a deferred attempt is not stamped, so launchd retries shortly.
      if [ "$force" -eq 0 ] && ! ${lib.getExe macosNixMaintenance.readyCheck}; then
        exit 0
      fi

      # GC and self-update share one PID-aware lock. Checking readiness before
      # and after acquiring it keeps the common deferral path cheap while also
      # closing the race where both jobs observe available headroom together.
      maintenance_state_dir=${lib.escapeShellArg macosNixMaintenance.stateDir}
      lock_file=${lib.escapeShellArg macosNixMaintenance.lockFile}
      mkdir -p "$maintenance_state_dir"

      if ! /usr/bin/shlock -f "$lock_file" -p $$; then
        echo "Another Nix maintenance job is active; deferring self-update."
        exit 0
      fi
      release_lock() {
        lock_pid=$(cat "$lock_file" 2>/dev/null || true)
        if [ "$lock_pid" = "$$" ]; then
          rm -f "$lock_file"
        fi
      }
      trap release_lock EXIT
      trap 'exit 130' INT
      trap 'exit 143' TERM

      if [ "$force" -eq 0 ] && ! ${lib.getExe macosNixMaintenance.readyCheck}; then
        exit 0
      fi

      if [ ! -d "$repo_dir/.git" ]; then
        rm -rf "$repo_dir"
        git clone --branch "$branch" "$flake_url" "$repo_dir"
      else
        git -C "$repo_dir" fetch --prune origin "$branch"
        git -C "$repo_dir" checkout -B "$branch" "origin/$branch"
        git -C "$repo_dir" clean -ffdx
      fi

      latest_rev=$(git -C "$repo_dir" rev-parse HEAD)
      echo "Building suremac from $flake_url at $latest_rev"

      # A fetch can take long enough for the user or another agent to begin
      # work. Re-check immediately before the first Nix command.
      if [ "$force" -eq 0 ] && ! ${lib.getExe macosNixMaintenance.readyCheck}; then
        exit 0
      fi
      nix build --accept-flake-config --print-build-logs --out-link "$out_link" \
        "$repo_dir#darwinConfigurations.suremac.system"

      new_system=$(readlink "$out_link")
      current_system=$(readlink /run/current-system)
      echo "Current system: $current_system"
      echo "Built system: $new_system"

      if [ "$new_system" = "$current_system" ]; then
        date +%s >"$last_run_file"
        echo "suremac is already running the built system; no activation needed."
        exit 0
      fi

      # Building may consume the available headroom. Keep the completed closure
      # rooted by the out-link, but defer interactive activation until the load
      # settles. A forced run intentionally bypasses this check.
      if [ "$force" -eq 0 ] && ! ${lib.getExe macosNixMaintenance.readyCheck}; then
        exit 0
      fi

      # A no-op or any activation attempt consumes the daily cadence. Busy
      # deferrals and transient fetch/build failures do not.
      date +%s >"$last_run_file"

      notify "dotfiles self-update" "A new suremac system was built and activation is starting."

      activate() {
        export SUDO_ASKPASS=${lib.escapeShellArg (lib.getExe askpass)}
        # sudo passes its prompt to the askpass helper as $1; without -p the
        # dialog would just say "Password:" with no context.
        local sudo_prompt="dotfiles self-update needs your macOS password to activate the new suremac system."
        # `|| return` is required: errexit is suspended inside a function
        # called as an `if` condition, so without it a failed (for example
        # cancelled) first sudo would fall through to the second one.
        # NIX_REMOTE=daemon matches darwin-rebuild, which forces the daemon
        # even as root; relevant here because Determinate Nix owns the daemon.
        /usr/bin/sudo -A -p "$sudo_prompt" /usr/bin/env NIX_REMOTE=daemon \
          ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/system --set "$new_system" || return
        /usr/bin/sudo -A -p "$sudo_prompt" "$new_system/activate"
      }

      # If activation restarts this agent (because the self-update job itself
      # changed), this script dies here and the notify agent picks up the
      # marker to report the outcome.
      printf '%s %s %s\n' "$new_system" "$latest_rev" "$(date +%s)" >"$marker"

      if activate; then
        rm -f "$marker"
        notify "dotfiles self-update" "suremac was updated successfully."
        echo "Successfully activated $new_system"
      else
        status=$?
        rm -f "$marker"
        notify "dotfiles self-update failed" "Activation failed or was cancelled. See ${logPath}."
        exit "$status"
      fi
    '';
  };
in {
  # On PATH so `dotfiles-suremac-self-update --force` can be run manually.
  environment.systemPackages = [selfUpdate];

  launchd.user.agents.dotfiles-suremac-self-update.serviceConfig = {
    ProgramArguments = [(lib.getExe selfUpdate)];
    StartInterval = 300;
    RunAtLoad = true;
    ProcessType = "Background";
    LowPriorityIO = true;
    StandardOutPath = logPath;
    StandardErrorPath = logPath;
  };

  launchd.user.agents.dotfiles-self-update-notify.serviceConfig = {
    ProgramArguments = [(lib.getExe reconcile) "--wait"];
    # RunAtLoad is the trigger: nix-darwin activation only reloads launchd
    # agents whose plists changed, and reloading the self-update agent kills
    # a self-update run mid-activation. DOTFILES_SELF_UPDATE_AGENT below ties
    # this plist's content to the self-update agent's config, so this agent is
    # reloaded (and fired) in exactly that scenario, polls until activation
    # completes, and reports the outcome the killed run could not.
    # (WatchPaths on /run/current-system does not work here: launchd's kqueue
    # watch follows the symlink to the target vnode, so an ln -sfn swap of the
    # symlink itself never fires. Verified empirically.)
    RunAtLoad = true;
    EnvironmentVariables.DOTFILES_SELF_UPDATE_AGENT =
      builtins.hashString "sha256"
      (builtins.toJSON config.launchd.user.agents.dotfiles-suremac-self-update.serviceConfig);
    ProcessType = "Background";
    StandardOutPath = logPath;
    StandardErrorPath = logPath;
  };
}
