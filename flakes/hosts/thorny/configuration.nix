{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  # Hyprland's upstream Nix package reads VERSION from its fileset-filtered
  # source while constructing GIT_TAG. With --no-build evaluation this can try
  # to read an unrealised source store path, so provide the tag from the flake
  # source directly instead.
  hyprlandPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland.overrideAttrs (old: {
    env =
      (old.env or {})
      // {
        GIT_TAG = "v${lib.removeSuffix "\n" (builtins.readFile "${inputs.hyprland}/VERSION")}";
      };
  });

  thornyStatus = pkgs.writeShellApplication {
    name = "thorny-status";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      gnused
      lm_sensors
      nix
      procps
      systemd
      tailscale
      util-linux
    ];
    text = ''
      set -uo pipefail

      section() { printf '\n== %s ==\n' "$*"; }

      section "Host"
      hostnamectl --static 2>/dev/null || hostname
      uptime

      section "Load and memory"
      printf 'Load average: '
      cut -d' ' -f1-3 /proc/loadavg
      free -h

      section "Disk"
      df -h / /nix 2>/dev/null || df -h /

      section "Nix store"
      du -sh /nix/store 2>/dev/null || true

      section "Active Nix builds"
      if pgrep -af 'nix build|nix-store|nix .*realise|nix .*realize|nix-daemon --stdio' >/dev/null; then
        pgrep -af 'nix build|nix-store|nix .*realise|nix .*realize|nix-daemon --stdio'
      else
        echo "No obvious active Nix build processes."
      fi

      section "Thermals"
      sensors 2>/dev/null || echo "No sensors output available."

      section "System76 power"
      systemctl --no-pager --lines=0 status system76-power.service 2>/dev/null \
        | sed -n '1,6p' \
        || echo "system76-power.service is unavailable or inactive."

      section "Tailscale"
      tailscale status --peers=false 2>/dev/null || echo "Tailscale status unavailable."
    '';
  };

  averagechrisSiteRefresh = pkgs.writeShellApplication {
    name = "averagechris-site-refresh";
    runtimeInputs = with pkgs; [
      coreutils
      git
      hut
      python3
    ];
    text = ''
      set -euo pipefail

      python3 - <<'PY'
      import json
      import os
      import re
      import subprocess
      import sys
      import tempfile
      import urllib.error
      import urllib.request

      try:
          import tomllib
      except ModuleNotFoundError:
          import tomli as tomllib

      STATE_URL = "https://averagechris.srht.site/state.json"
      FLEET_URL = "https://git.sr.ht/~averagechris/averagechris.srht.site/blob/main/fleet.toml"
      MANIFEST_URL = "https://git.sr.ht/~averagechris/averagechris.srht.site/blob/main/.builds/refresh-pages.yml"
      REPO_BASE = "https://git.sr.ht/~averagechris"
      TRIGGER_SOURCE = "thorny-timer"

      semver_tag = re.compile(r"^refs/tags/v([0-9]+)\.([0-9]+)\.([0-9]+)$")

      def fetch_bytes(url):
          request = urllib.request.Request(url, headers={"User-Agent": "thorny fleet pages refresh"})
          with urllib.request.urlopen(request, timeout=30) as response:
              return response.read()

      def fetch_text(url):
          return fetch_bytes(url).decode("utf-8")

      stale_reasons = []
      try:
          state = json.loads(fetch_text(STATE_URL))
          if not isinstance(state, dict):
              raise ValueError("state.json top-level value is not an object")
      except Exception as exc:
          state = {}
          stale_reasons.append(f"state.json unavailable or invalid: {exc}")

      fleet = tomllib.loads(fetch_text(FLEET_URL))
      projects = fleet.get("repos", fleet.get("project", fleet.get("projects", [])))
      if isinstance(projects, dict):
          projects = list(projects.values())

      repos = []
      for project in projects:
          if not isinstance(project, dict):
              continue
          name = project.get("name")
          repo = project.get("srht_repo") or name
          if repo:
              repos.append({
                  "name": str(name or repo),
                  "repo": str(repo),
                  "fallback_repo": str(project.get("pages_subdir") or ""),
              })

      if not repos:
          raise RuntimeError("fleet.toml did not contain any srht_repo/name entries")

      def latest_remote_pins(repo):
          output = subprocess.check_output(
              ["git", "ls-remote", f"{REPO_BASE}/{repo}"],
              stderr=subprocess.DEVNULL,
              text=True,
              timeout=60,
          )
          latest_tag = None
          latest_version = None
          main_sha = None
          for line in output.splitlines():
              sha, ref = line.split("\t", 1)
              if ref == "refs/heads/main":
                  main_sha = sha
              match = semver_tag.match(ref)
              if match:
                  version = tuple(int(part) for part in match.groups())
                  if latest_version is None or version > latest_version:
                      latest_version = version
                      latest_tag = ref.removeprefix("refs/tags/")
          return {"tag": latest_tag, "main_sha": main_sha}

      for project in repos:
          repo = project["repo"]
          try:
              remote = latest_remote_pins(repo)
          except Exception as exc:
              fallback_repo = project["fallback_repo"]
              if fallback_repo and fallback_repo != repo:
                  try:
                      repo = fallback_repo
                      remote = latest_remote_pins(repo)
                  except Exception as fallback_exc:
                      stale_reasons.append(
                          f"{project['name']}: failed to query {project['repo']!r} ({exc}) "
                          f"or fallback {fallback_repo!r} ({fallback_exc})"
                      )
                      continue
              else:
                  stale_reasons.append(f"{project['name']}: failed to query {repo!r}: {exc}")
                  continue
          # state.json nests per-project pins under "projects", keyed by
          # pages_subdir (== name for every repo except slack-rs, whose
          # srht_repo matches its subdir).
          projects_state = state.get("projects") if isinstance(state.get("projects"), dict) else {}
          published = projects_state.get(project["name"], projects_state.get(repo, {}))
          if published.get("tag") != remote["tag"] or published.get("main_sha") != remote["main_sha"]:
              stale_reasons.append(
                  f"{project['name']}: published tag={published.get('tag')!r} main_sha={published.get('main_sha')!r}; "
                  f"remote tag={remote['tag']!r} main_sha={remote['main_sha']!r}"
              )

      if not stale_reasons:
          print("fleet pages up to date")
          sys.exit(0)

      print("fleet pages stale:")
      for reason in stale_reasons:
          print(f"- {reason}")

      manifest = fetch_text(MANIFEST_URL)
      lines = manifest.splitlines()
      env_index = next((index for index, line in enumerate(lines) if line == "environment:"), None)
      if env_index is None:
          lines.extend(["environment:", f"  TRIGGER_SOURCE: {TRIGGER_SOURCE}"])
      else:
          insert_at = env_index + 1
          while insert_at < len(lines) and (lines[insert_at].startswith("  ") or not lines[insert_at].strip()):
              insert_at += 1
          env_lines = lines[env_index + 1 : insert_at]
          replaced = False
          for offset, line in enumerate(env_lines, start=env_index + 1):
              if re.match(r"^  TRIGGER_SOURCE:", line):
                  lines[offset] = f"  TRIGGER_SOURCE: {TRIGGER_SOURCE}"
                  replaced = True
                  break
          if not replaced:
              lines.insert(insert_at, f"  TRIGGER_SOURCE: {TRIGGER_SOURCE}")
      manifest = "\n".join(lines) + "\n"

      if os.environ.get("DRY_RUN"):
          print("DRY_RUN set; would submit SourceHut build manifest:")
          print(manifest)
          sys.exit(0)

      with tempfile.NamedTemporaryFile("w", delete=False) as handle:
          handle.write(manifest)
          manifest_path = handle.name
      try:
          subprocess.check_call([
              "hut",
              "builds",
              "submit",
              "--visibility",
              "unlisted",
              "--note",
              "fleet pages refresh (thorny timer)",
              manifest_path,
          ])
      finally:
          os.unlink(manifest_path)
      PY
    '';
  };

  hutConfig = pkgs.writeText "thorny-hut-config" ''
    instance "sr.ht" {
      access-token-cmd ${pkgs.coreutils}/bin/cat ${config.age.secrets.hut-access-token.path}
    }
  '';

  dotfilesHostBuildCache = pkgs.writeShellApplication {
    name = "dotfiles-host-build-cache";
    runtimeInputs = with pkgs; [
      coreutils
      git
      nix
      util-linux
    ];
    text = ''
      set -euo pipefail

      state_dir="/var/lib/dotfiles-host-build-cache"
      result_dir="$state_dir/results"
      log_dir="$state_dir/logs"
      lock_file="$state_dir/build.lock"
      flake_ref="git+https://git.sr.ht/~averagechris/dotfiles?ref=main"

      mkdir -p "$result_dir" "$log_dir"

      exec 9>"$lock_file"
      if ! flock -n 9; then
        echo "Another dotfiles host build-cache run is already active; exiting."
        exit 0
      fi

      hosts=(
        trap
        thorny
        tom
        cruber
        tater
        trainwreck
      )

      failed=0
      for host in "''${hosts[@]}"; do
        log="$log_dir/$host.log"
        echo "== Building $host from $flake_ref =="
        if nix build \
          --accept-flake-config \
          --print-build-logs \
          --out-link "$result_dir/$host" \
          "$flake_ref#nixosConfigurations.$host.config.system.build.toplevel" \
          > >(tee "$log") \
          2> >(tee -a "$log" >&2); then
          echo "Built $host: $(readlink "$result_dir/$host")"
        else
          echo "Failed to build $host; see $log" >&2
          failed=1
        fi
      done

      exit "$failed"
    '';
  };

  dotfilesThornySelfDeploy = pkgs.writeShellApplication {
    name = "dotfiles-thorny-self-deploy";
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

      state_dir="/var/lib/dotfiles-thorny-self-deploy"
      lock_file="$state_dir/deploy.lock"
      last_success_rev_file="$state_dir/last-success-rev"
      last_attempt_rev_file="$state_dir/last-attempt-rev"
      last_failure_rev_file="$state_dir/last-failure-rev"
      flake_ref="git+https://git.sr.ht/~averagechris/dotfiles?ref=main"
      attr="nixosConfigurations.thorny.config.system.build.toplevel"

      mkdir -p "$state_dir"

      exec 9>"$lock_file"
      if ! flock -n 9; then
        echo "Another thorny self-deploy run is already active; exiting."
        exit 0
      fi

      latest_rev=$(nix flake metadata --json "$flake_ref" | jq -r '.revision // .locked.rev // empty')
      if [ -z "$latest_rev" ]; then
        echo "Could not determine latest revision for $flake_ref" >&2
        exit 1
      fi

      if [ -f "$last_success_rev_file" ] && [ "$(cat "$last_success_rev_file")" = "$latest_rev" ]; then
        echo "thorny is already deployed at $latest_rev"
        exit 0
      fi

      printf '%s\n' "$latest_rev" >"$last_attempt_rev_file"

      previous_system=$(readlink -f /run/current-system)
      echo "Previous system: $previous_system"
      echo "Building thorny from $flake_ref at $latest_rev"

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

        for unit in sshd.service tailscaled.service nix-daemon.service NetworkManager.service; do
          if ! systemctl is-active --quiet "$unit"; then
            echo "Required unit is not active: $unit" >&2
            failed=1
          fi
        done

        if ! systemctl is-system-running --quiet; then
          state=$(systemctl is-system-running || true)
          echo "System state after activation: $state" >&2
          systemctl --failed --no-pager >&2 || true
          failed=1
        fi

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
        echo "Successfully deployed thorny at $latest_rev"
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
  fleetCacheWarmer = pkgs.writeShellApplication {
    name = "fleet-cache-warmer";
    runtimeInputs = with pkgs; [
      cachix
      coreutils
      git
      nix
      util-linux
    ];
    text = ''
      set -euo pipefail

      state_dir="/var/lib/fleet-cache-warmer"
      lock_file="$state_dir/warm.lock"
      token_file=${lib.escapeShellArg config.age.secrets.cachix-auth-token.path}
      cache_name="averagechris-dotfiles"
      repo_base="https://git.sr.ht/~averagechris"

      mkdir -p "$state_dir"

      exec 9>"$lock_file"
      if ! flock -n 9; then
        echo "Another fleet cache warmer run is already active; exiting."
        exit 0
      fi

      if [ ! -r "$token_file" ]; then
        echo "cachix token file missing or unreadable at $token_file; skipping"
        exit 0
      fi
      if [ "$(cat "$token_file")" = "REPLACE_ME" ]; then
        echo "cachix token not provisioned yet; skipping"
        exit 0
      fi

      CACHIX_AUTH_TOKEN="$(cat "$token_file")"
      export CACHIX_AUTH_TOKEN

      # Build a flake output from the current main of a sourcehut repo and
      # push its closure to cachix, skipping if that rev was already pushed.
      warm() {
        local name="$1" repo="$2" attr="$3"
        local rev_file="$state_dir/last-pushed-$name"
        local rev out_paths

        if ! rev=$(git ls-remote "$repo_base/$repo" refs/heads/main | cut -f1) \
          || [ -z "$rev" ]; then
          echo "Failed to resolve main rev for $repo" >&2
          return 1
        fi

        if [ -f "$rev_file" ] && [ "$(cat "$rev_file")" = "$rev" ]; then
          echo "$name#$attr already pushed at $rev"
          return 0
        fi

        echo "== Warming $name#$attr at $rev =="
        if ! out_paths=$(nix build \
          --accept-flake-config \
          --no-link \
          --print-out-paths \
          "git+$repo_base/$repo?ref=main&rev=$rev#$attr"); then
          echo "Failed to build $name#$attr at $rev" >&2
          return 1
        fi

        if ! printf '%s\n' "$out_paths" | cachix push "$cache_name"; then
          echo "Failed to push $name closure to $cache_name" >&2
          return 1
        fi

        printf '%s\n' "$rev" >"$rev_file"
        echo "Pushed $name#$attr at $rev"
      }

      failures=()

      # The hourly refresh-pages CI job substitutes this closure instead of
      # rebuilding the site tooling on builds.sr.ht.
      warm averagechris.srht.site averagechris.srht.site fleet-ci-closure \
        || failures+=("averagechris.srht.site")

      fleet_repos=(
        linear-cli
        slack
        granola-cli
        ctx
        starship-jj
        workctl
        gander
      )
      for repo in "''${fleet_repos[@]}"; do
        warm "$repo" "$repo" release-artifact || failures+=("$repo")
      done

      if [ "''${#failures[@]}" -gt 0 ]; then
        echo "fleet cache warmer failed for: ''${failures[*]}" >&2
        exit 1
      fi

      echo "fleet cache warmer complete"
    '';
  };

  histerBackup = pkgs.writeShellApplication {
    name = "hister-backup";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gnutar
      systemd
      zstd
    ];
    text = ''
      set -euo pipefail

      backup_dir="/var/backups/hister"
      keep=14

      systemctl stop hister.service
      trap 'systemctl start hister.service' EXIT

      tar --zstd -cf "$backup_dir/hister-$(date +%Y%m%d).tar.zst" -C /var/lib hister

      # Prune to the newest $keep archives. Date-stamped names sort
      # lexicographically in chronological order.
      mapfile -t archives < <(find "$backup_dir" -maxdepth 1 -name 'hister-*.tar.zst' | sort -r)
      if [ "''${#archives[@]}" -gt "$keep" ]; then
        for old in "''${archives[@]:$keep}"; do
          rm -f "$old"
        done
      fi
    '';
  };
in {
  imports = [
    inputs.nixos-modules.nixosModules.common
    inputs.nixos-modules.nixosModules.desktopCommon
    inputs.nixos-modules.nixosModules.networking
    inputs.nixos-modules.nixosModules.sound
    inputs.nixos-modules.nixosModules.sudoDeploy
    inputs.nixos-modules.nixosModules.tailscale
    inputs.nixos-modules.nixosModules.virtualization
    inputs.nixos-modules.nixosModules.isRemoteBuilder
    inputs.nixos-modules.nixosModules.users.chris
    inputs.nixos-modules.nixosModules.hyprlandDesktop
    inputs.hister.nixosModules.hister
    ./hardware.nix
    inputs.agenix.nixosModules.default
    inputs.nixos-hardware.nixosModules.system76
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-gpu-amd
    inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate
    inputs.nixos-hardware.nixosModules.common-pc-ssd
  ];

  dotfiles.hyprland-desktop.enable = true;
  programs.hyprland.package = hyprlandPackage;
  xdg.portal.extraPortals = lib.mkForce [
    inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland
    pkgs.xdg-desktop-portal-gtk
  ];

  boot.initrd.luks.devices.root.device = "/dev/sda2";
  networking.hostName = "thorny";

  networking.wireless.interfaces = ["wlp6s0"];

  environment.systemPackages = with pkgs; [
    lm_sensors
    mesa
    nvme-cli
    smartmontools
    thornyStatus
  ];
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.enableRedistributableFirmware = true;
  hardware.system76.enableAll = true;

  # Allow thorny to build trainwreck's aarch64-linux system closure locally via
  # binfmt/QEMU when invoked directly on thorny, and allow other clients to use
  # thorny as an emulated aarch64-linux remote builder.
  boot.binfmt.emulatedSystems = ["aarch64-linux"];

  # Passwordless sudo for deploy-rs / remote rebuilds from trusted SSH keys.
  dotfiles.sudoNoPassword.enable = true;

  nix.settings = {
    # Thorny/thelio is intended to be a high-core-count remote builder. Allow
    # trusted SSH users to submit builds and let the local daemon use all CPUs.
    trusted-users = ["@wheel" "chris"];
    max-jobs = "auto";
    cores = 0;
    extra-platforms = ["aarch64-linux"];
    min-free = 20 * 1024 * 1024 * 1024;
    max-free = 100 * 1024 * 1024 * 1024;
  };

  services.fwupd.enable = true;

  # Hister — self-hosted personal web search engine. Served publicly at
  # https://hister.thesogu.com via Caddy on trainwreck, which reverse-proxies
  # to thorny over the tailnet. Port 4433 is intentionally NOT opened in the
  # firewall: the shared tailscale module trusts tailscale0, so trainwreck can
  # reach it while the LAN stays blocked.
  #
  # The hut token is read by hut's normal user config below when submitting
  # SourceHut build jobs as chris.
  #
  # The encrypted hister env file may not exist yet (create it with
  # `agenix -e secrets/thorny/hister-env.age`; it is registered in
  # secrets/secrets.nix). Guard on existence so the config evaluates before
  # the secret is created; once the file is committed, the secret and
  # environmentFile wire up automatically.
  age.secrets =
    {
      # Cachix auth token for the fleet-cache-warmer service below. Readable
      # by chris because the warmer runs as chris. Ships as the placeholder
      # REPLACE_ME until provisioned; the warmer skips itself until then.
      cachix-auth-token = {
        file = ../../../secrets/cachix-auth-token.age;
        owner = "chris";
        group = "users";
        mode = "0400";
      };

      hut-access-token = {
        file = ../../../secrets/thorny/hut-access-token.age;
        owner = "chris";
        group = "users";
        mode = "0400";
      };
    }
    // lib.optionalAttrs (builtins.pathExists ../../../secrets/thorny/hister-env.age) {
      hister-env = {
        file = ../../../secrets/thorny/hister-env.age;
        # Read by systemd as root via EnvironmentFile.
        mode = "0400";
      };
    };

  services.hister = {
    enable = true;
    # Contains HISTER__SERVER__OAUTH__GITHUB__CLIENT_SECRET=...
    environmentFile =
      lib.mkIf (builtins.pathExists ../../../secrets/thorny/hister-env.age)
      config.age.secrets.hister-env.path;
    settings = {
      app.user_handling = true;
      server = {
        address = "0.0.0.0:4433";
        base_url = "https://hister.thesogu.com";
        oauth_only = true;
        oauth.github = {
          # The client_id is not secret; fill in after creating the GitHub
          # OAuth app (callback:
          # https://hister.thesogu.com/api/oauth/callback?provider=github).
          # The client_secret comes from the environmentFile above.
          client_id = "REPLACE-WITH-GITHUB-OAUTH-CLIENT-ID";
          allowed_users = ["averagechris"]; # extend with friends' GitHub logins
        };
      };
    };
  };

  # Nightly hister backup: stop the service, archive its state directory
  # (/var/lib/hister via StateDirectory), restart, and prune old archives.
  systemd.services.hister-backup = {
    description = "Back up hister state to /var/backups/hister";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe histerBackup;
    };
  };

  systemd.timers.hister-backup = {
    description = "Nightly hister state backup";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "15m";
      Unit = "hister-backup.service";
    };
  };

  systemd.services.averagechris-site-refresh = {
    description = "Submit a SourceHut fleet pages refresh build when the published site is stale";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "chris";
      Environment = [
        "HOME=/home/chris"
        "XDG_CONFIG_HOME=/home/chris/.config"
      ];
      ExecStart = lib.getExe averagechrisSiteRefresh;
    };
  };

  systemd.timers.averagechris-site-refresh = {
    description = "Hourly fleet pages refresh safety-net check";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
      RandomizedDelaySec = "5m";
      Unit = "averagechris-site-refresh.service";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/dotfiles-host-build-cache 0755 chris users - -"
    "d /var/lib/dotfiles-host-build-cache/results 0755 chris users - -"
    "d /var/lib/dotfiles-host-build-cache/logs 0755 chris users - -"
    "d /var/lib/dotfiles-thorny-self-deploy 0755 root root - -"
    "d /var/lib/fleet-cache-warmer 0755 chris users - -"
    "d /var/backups/hister 0700 root root - -"
  ];

  systemd.services.dotfiles-host-build-cache = {
    description = "Keep current dotfiles host system builds realized on thorny";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "chris";
      WorkingDirectory = "/var/lib/dotfiles-host-build-cache";
      ExecStart = lib.getExe dotfilesHostBuildCache;
      Nice = 10;
      IOSchedulingClass = "best-effort";
      IOSchedulingPriority = 6;
    };
  };

  systemd.timers.dotfiles-host-build-cache = {
    description = "Regularly build current dotfiles host systems on thorny";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "30m";
      OnUnitActiveSec = "6h";
      Persistent = true;
      RandomizedDelaySec = "30m";
      Unit = "dotfiles-host-build-cache.service";
    };
  };

  systemd.services.fleet-cache-warmer = {
    description = "Push fleet CI closures from sourcehut main branches to cachix";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "chris";
      Environment = [
        "HOME=/home/chris"
        "XDG_CONFIG_HOME=/home/chris/.config"
      ];
      WorkingDirectory = "/var/lib/fleet-cache-warmer";
      ExecStart = lib.getExe fleetCacheWarmer;
      # Rust release-artifact builds can take a long time on a cold store.
      TimeoutStartSec = "4h";
      Nice = 10;
      IOSchedulingClass = "best-effort";
      IOSchedulingPriority = 6;
    };
  };

  systemd.timers.fleet-cache-warmer = {
    description = "Hourly fleet CI closure cache warm-up";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
      RandomizedDelaySec = "10m";
      Unit = "fleet-cache-warmer.service";
    };
  };

  systemd.services.dotfiles-thorny-self-deploy = {
    description = "Pull and activate the latest thorny system from dotfiles main";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe dotfilesThornySelfDeploy;
      Nice = 10;
      IOSchedulingClass = "best-effort";
      IOSchedulingPriority = 6;
    };
  };

  systemd.timers.dotfiles-thorny-self-deploy = {
    description = "Regularly self-deploy thorny from dotfiles main";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "45m";
      OnUnitActiveSec = "2h";
      Persistent = true;
      RandomizedDelaySec = "15m";
      Unit = "dotfiles-thorny-self-deploy.service";
    };
  };

  # Thorny is a remote builder: displays may turn off and the session may lock,
  # but the machine itself should remain reachable for SSH and build jobs.
  services.logind.settings.Login.IdleAction = "ignore";
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  programs.steam.enable = true;
  programs.gamemode.enable = true;
  hardware.xone.enable = true;

  users.users.chris.extraGroups = ["libvirtd" "podman"];

  system.stateVersion = "26.05";
  home-manager.users.chris = {lib, ...}: {
    home.stateVersion = "26.05";
    imports = [
      inputs.hm-modules.homeManagerModules.default
      inputs.pip-chrome-extension.homeManagerModules.default
      inputs.hm-modules.homeManagerModules.ghostty-fix
    ];

    systemd.user.startServices = true;
    systemd.user.services = lib.listToAttrs (map (name:
      lib.nameValuePair name {
        Unit.RefuseManualStart = lib.mkForce true;
      }) [
      "hyprpaper"
      "hypridle"
      "hctl"
      "swaync"
      "network-manager-applet"
      "udiskie"
      "mako"
      "gammastep"
      "com.mitchellh.ghostty"
      "mega-cmd-server-init"
    ]);

    dotfiles.hyprland-workstation.enable = true;
    dotfiles.hyprland-workstation.terminal = "ghostty";
    dotfiles.gander.enable = true;
    # sccache + daily cleanup (nix user GC, cargo sweep); docker pruning is
    # not useful here (podman host, little container churn).
    dotfiles.devCache = {
      enable = true;
      docker.enable = false;
    };
    dotfiles.gui.swayidle.enable = false;
    dotfiles.gui.hyprland.waybar.enable = false;
    wayland.windowManager.hyprland.package = hyprlandPackage;
    dotfiles.gui.hyprland.overview = {
      enable = false;
      package = null;
    };

    dotfiles.hypridle.timeouts = {
      dim = 600;
      lock = 1800;
      dpms = 2700;
      suspend = 0;
      hibernate = 0;
    };

    programs.meganz.enable = true;
    programs.helium.enable = true;
    programs.helium.extension-simple-pip-helper.enable = true;

    dotfiles.shell.yazi.enable = true;
    programs.opencode.enable = true;
    xdg.configFile."hut/config".source = hutConfig;
    services.network-manager-applet.enable = true;
    home.packages = [pkgs.claude-code pkgs.hut];
  };
}
