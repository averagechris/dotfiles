{
  pkgs,
  user,
  blockCacheClients ? false,
  maxLoadPercent ? 60,
}: let
  stateDir = "/Users/${user}/.local/state/dotfiles-nix-maintenance";
  blockCacheClientsInt =
    if blockCacheClients
    then "1"
    else "0";
  readyCheck = pkgs.writeShellApplication {
    name = "dotfiles-nix-maintenance-ready";
    text = ''
      set -uo pipefail

      active=$(
        /bin/ps -ww -axo pid=,state=,ucomm=,args= | /usr/bin/awk '
          function base(path) {
            sub(/^.*\//, "", path)
            return path
          }

          function is_nix_client(name) {
            return name == "nix" ||
                   name == "nix-build" ||
                   name == "nix-channel" ||
                   name == "nix-collect-garbage" ||
                   name == "nix-copy-closure" ||
                   name == "nix-env" ||
                   name == "nix-instantiate" ||
                   name == "nix-prefetch-url" ||
                   name == "nix-shell" ||
                   name == "nix-store" ||
                   name == "darwin-rebuild" ||
                   name == "nixos-rebuild" ||
                   name == "home-manager" ||
                   name == "devenv" ||
                   name == "nh" ||
                   name == "nom"
          }

          function is_cache_client(name) {
            return name == "cargo" ||
                   name == "rustc" ||
                   name == "docker"
          }

          function is_shell(name) {
            return name == "bash" ||
                   name == "dash" ||
                   name == "sh" ||
                   name == "zsh"
          }

          $2 !~ /^Z/ {
            name = base($3)
            argv0 = base($4)
            busy = is_nix_client(name) || is_nix_client(argv0)
            if (${blockCacheClientsInt})
              busy = busy || is_cache_client(name) || is_cache_client(argv0)
            if (is_shell(name) || is_shell(argv0)) {
              script = base($5)
              busy = busy || is_nix_client(script)
              if (${blockCacheClientsInt})
                busy = busy || is_cache_client(script)
            }

            # The modern multi-call executable can host the resident daemon.
            # Do not mistake it for a client unless this is a --stdio remote
            # store connection.
            if (name == "nix" || argv0 == "nix") {
              stdio = 0
              for (i = 5; i <= NF; i++) {
                if ($i == "--stdio")
                  stdio = 1
              }
              if ($5 == "daemon")
                busy = stdio
            }

            # The ordinary nix-daemon is always resident. A --stdio daemon is
            # an active remote-store connection and should block maintenance.
            if (name == "nix-daemon" || argv0 == "nix-daemon") {
              busy = 0
              for (i = 4; i <= NF; i++)
                if ($i == "--stdio")
                  busy = 1
            }

            if (busy)
              print $1 "/" name
          }
        '
      ) || {
        printf 'maintenance deferred: could not inspect running processes\n' >&2
        exit 75
      }

      if [ -n "$active" ]; then
        printf 'maintenance deferred: active client(s): %s\n' "$(printf '%s\n' "$active" | /usr/bin/tr '\n' ' ')" >&2
        exit 75
      fi

      cpu_count=$(/usr/sbin/sysctl -n hw.logicalcpu 2>/dev/null || true)
      load_one=$(
        /usr/sbin/sysctl -n vm.loadavg 2>/dev/null |
          /usr/bin/awk '{ print $2 }'
      ) || true

      if ! [[ "$cpu_count" =~ ^[1-9][0-9]*$ ]] || ! [[ "$load_one" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        printf 'maintenance deferred: CPU headroom could not be inspected\n' >&2
        exit 75
      fi

      if ! /usr/bin/awk -v load="$load_one" -v cpus="$cpu_count" -v max_percent=${toString maxLoadPercent} \
        'BEGIN { exit !((load * 100) < (cpus * max_percent)) }'; then
        printf 'maintenance deferred: 1-minute load %s exceeds %s%% of %s logical CPUs\n' \
          "$load_one" ${toString maxLoadPercent} "$cpu_count" >&2
        exit 75
      fi
    '';
  };
in {
  inherit readyCheck stateDir;
  lockFile = "${stateDir}/lock";
}
