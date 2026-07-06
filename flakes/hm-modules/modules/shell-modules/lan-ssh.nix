{
  config,
  lib,
  pkgs,
  dotfiles_lib,
  ...
}: let
  cfg = config.dotfiles.shell.lanSsh;

  safeSshOptions = ''
    -o BatchMode=yes
    -o PasswordAuthentication=no
    -o ConnectTimeout="''${DOTFILES_LAN_SSH_CONNECT_TIMEOUT:-2}"
    -o ConnectionAttempts=1
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o CheckHostIP=no
    -o UpdateHostKeys=no
    -o LogLevel=ERROR
  '';

  dotfilesLanHosts = pkgs.writeShellApplication {
    name = "dotfiles-lan-hosts";
    runtimeInputs = [pkgs.coreutils pkgs.openssh];
    text = ''
      set -euo pipefail

      user="''${DOTFILES_LAN_SSH_USER:-chris}"
      print_ip_only=false
      requested_host=""

      usage() {
        cat <<'EOF'
      Usage:
        dotfiles-lan-hosts [HOST]
        dotfiles-lan-hosts --ip HOST

      Scans likely local IPv4 addresses with a noninteractive SSH probe and prints
      reachable dotfiles hosts as: HOST<TAB>IP.

      Environment:
        DOTFILES_LAN_SUBNETS="192.168.4"   Space-separated /24 prefixes to scan.
        DOTFILES_LAN_IPS="192.168.4.28"   Extra exact IPs to try first.
        DOTFILES_LAN_SCAN_JOBS=64          Concurrent SSH probes.
        DOTFILES_LAN_SSH_USER=chris        SSH user for probes.
      EOF
      }

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --help|-h)
            usage
            exit 0
            ;;
          --ip)
            print_ip_only=true
            requested_host="''${2:-}"
            if [[ -z "$requested_host" ]]; then
              printf 'dotfiles-lan-hosts: --ip requires HOST\n' >&2
              exit 2
            fi
            shift 2
            ;;
          *)
            requested_host="$1"
            shift
            ;;
        esac
      done

      safe_ssh_options=(
        ${safeSshOptions}
      )

      local_ipv4_addresses() {
        if command -v ip >/dev/null 2>&1; then
          ip -o -4 addr show scope global 2>/dev/null | while read -r _ _ _ address _; do
            printf '%s\n' "''${address%%/*}"
          done
        fi

        if command -v ifconfig >/dev/null 2>&1 || [[ -x /sbin/ifconfig ]]; then
          "$(command -v ifconfig || printf /sbin/ifconfig)" 2>/dev/null | while read -r first second _; do
            if [[ "$first" == "inet" && "$second" != "127."* ]]; then
              printf '%s\n' "$second"
            fi
          done
        fi
      }

      local_prefixes() {
        {
          for prefix in ''${DOTFILES_LAN_SUBNETS:-}; do
            printf '%s\n' "$prefix"
          done

          local_ipv4_addresses | while IFS=. read -r a b c _; do
            if [[ -n "''${a:-}" && -n "''${b:-}" && -n "''${c:-}" ]]; then
              printf '%s.%s.%s\n' "$a" "$b" "$c"
            fi
          done

          # Current home LAN hint. Keep this as a fallback only; dynamic discovery
          # above wins when the client is on another network.
          printf '192.168.4\n'
        } | sort -u
      }

      candidate_ips() {
        {
          for ip in ''${DOTFILES_LAN_IPS:-}; do
            printf '%s\n' "$ip"
          done

          # Recent/static hints first so common cases return quickly.
          printf '192.168.4.28\n'

          local_prefixes | while read -r prefix; do
            for suffix in $(seq 1 254); do
              printf '%s.%s\n' "$prefix" "$suffix"
            done
          done
        } | sort -u
      }

      tmpdir="$(mktemp -d)"
      cleanup() { rm -rf "$tmpdir"; }
      trap cleanup EXIT

      max_jobs="''${DOTFILES_LAN_SCAN_JOBS:-64}"
      if ! [[ "$max_jobs" =~ ^[0-9]+$ ]] || [[ "$max_jobs" -lt 1 ]]; then
        max_jobs=64
      fi

      probe() {
        local ip="$1"
        local host
        host="$(ssh "''${safe_ssh_options[@]}" "$user@$ip" 'hostname' 2>/dev/null || true)"
        host="''${host%%$'\n'*}"
        if [[ -n "$host" ]]; then
          printf '%s\t%s\n' "$host" "$ip" >"$tmpdir/$ip"
        fi
      }

      for ip in $(candidate_ips); do
        probe "$ip" &
        while [[ "$(jobs -pr | wc -l | tr -d ' ')" -ge "$max_jobs" ]]; do
          wait -n || true
        done
      done
      wait || true

      results="$(cat "$tmpdir"/* 2>/dev/null | sort -u || true)"

      if [[ -n "$requested_host" ]]; then
        results="$(printf '%s\n' "$results" | while IFS=$'\t' read -r host ip; do
          if [[ "$host" == "$requested_host" ]]; then
            printf '%s\t%s\n' "$host" "$ip"
          fi
        done)"
      fi

      if [[ "$print_ip_only" == true ]]; then
        if [[ -z "$results" ]]; then
          printf 'dotfiles-lan-hosts: no reachable host named %s\n' "$requested_host" >&2
          exit 1
        fi
        printf '%s\n' "$results" | head -n 1 | while IFS=$'\t' read -r _ ip; do
          printf '%s\n' "$ip"
        done
      else
        printf '%s\n' "$results"
      fi
    '';
  };

  sshLan = pkgs.writeShellApplication {
    name = "ssh-lan";
    runtimeInputs = [dotfilesLanHosts pkgs.openssh];
    text = ''
      set -euo pipefail

      if [[ $# -lt 1 || "''${1:-}" == "--help" || "''${1:-}" == "-h" ]]; then
        cat <<'EOF'
      Usage: ssh-lan HOST [SSH_ARGS...]

      Resolve HOST on the local network with dotfiles-lan-hosts, then SSH with
      host-key persistence disabled for DHCP-heavy LAN addresses.
      EOF
        exit 0
      fi

      host="$1"
      shift
      user="''${DOTFILES_LAN_SSH_USER:-chris}"
      ip="$(dotfiles-lan-hosts --ip "$host")"

      safe_ssh_options=(
        ${safeSshOptions}
      )

      exec ssh "''${safe_ssh_options[@]}" "$user@$ip" "$@"
    '';
  };

  mkHostWrapper = host:
    pkgs.writeShellApplication {
      name = "ssh-${host}-lan";
      runtimeInputs = [sshLan];
      text = ''
        exec ssh-lan ${host} "$@"
      '';
    };
in {
  options.dotfiles.shell.lanSsh.enable = dotfiles_lib.options.mkDefaultEnabledOption "Install DHCP-friendly local-network SSH discovery and safe SSH helpers.";

  config = lib.mkIf (config.dotfiles.shell.enable && cfg.enable) {
    home.packages = [
      dotfilesLanHosts
      sshLan
      (mkHostWrapper "thorny")
      (mkHostWrapper "tater")
      (mkHostWrapper "suremac")
    ];
  };
}
