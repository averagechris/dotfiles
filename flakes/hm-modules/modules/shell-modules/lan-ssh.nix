{
  config,
  lib,
  pkgs,
  dotfiles_lib,
  sshKeys ? {},
  ...
}: let
  cfg = config.dotfiles.shell.lanSsh;

  defaultHostKeys = lib.filterAttrs (_: key: key != null) {
    thorny = lib.attrByPath ["system" "thelio"] null sshKeys;
    tater = lib.attrByPath ["system" "tater"] null sshKeys;
    suremac = lib.attrByPath ["system" "suremac"] null sshKeys;
  };

  mkKnownHostsFile = name: keys:
    pkgs.writeText name (lib.concatMapStringsSep "\n" (key: "* ${key}") keys + "\n");

  discoveryKnownHosts = mkKnownHostsFile "dotfiles-lan-discovery-known-hosts" (builtins.attrValues cfg.hostKeys);
  hostKnownHosts = lib.mapAttrs (host: key: mkKnownHostsFile "dotfiles-lan-${host}-known-hosts" [key]) cfg.hostKeys;

  safeSshOptions = knownHostsFile: ''
    -o BatchMode=yes
    -o PasswordAuthentication=no
    -o ConnectTimeout="''${DOTFILES_LAN_SSH_CONNECT_TIMEOUT:-2}"
    -o ConnectionAttempts=1
    -o StrictHostKeyChecking=yes
    -o UserKnownHostsFile=${knownHostsFile}
    -o GlobalKnownHostsFile=/dev/null
    -o CheckHostIP=no
    -o UpdateHostKeys=no
    -o HostKeyAlgorithms=ssh-ed25519
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
      use_cache=true
      trusted_subnets="''${DOTFILES_LAN_TRUSTED_SUBNETS:-192.168.4}"
      allow_untrusted="''${DOTFILES_LAN_ALLOW_UNTRUSTED:-0}"

      usage() {
        cat <<'EOF'
      Usage:
        dotfiles-lan-hosts [HOST]
        dotfiles-lan-hosts --ip HOST
        dotfiles-lan-hosts --no-cache [HOST]

      Scans likely local IPv4 addresses with a noninteractive SSH probe and prints
      reachable dotfiles hosts as: HOST<TAB>IP.

      Environment:
        DOTFILES_LAN_SUBNETS="192.168.4"   Space-separated /24 prefixes to scan.
        DOTFILES_LAN_IPS="192.168.4.28"   Extra exact IPs to try first.
        DOTFILES_LAN_SCAN_JOBS=64          Concurrent SSH probes.
        DOTFILES_LAN_SSH_USER=chris        SSH user for probes.
        DOTFILES_LAN_CACHE_TTL=3600        Cache lifetime in seconds.
        DOTFILES_LAN_TRUSTED_SUBNETS=...   Allowed active /24 prefixes.
        DOTFILES_LAN_ALLOW_UNTRUSTED=1     Explicitly bypass the network guard.
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
            if [[ -z "$requested_host" || "$requested_host" == -* ]]; then
              printf 'dotfiles-lan-hosts: --ip requires HOST\n' >&2
              exit 2
            fi
            shift 2
            ;;
          --no-cache)
            use_cache=false
            shift
            ;;
          --*)
            printf 'dotfiles-lan-hosts: unknown option: %s\n' "$1" >&2
            exit 2
            ;;
          *)
            if [[ -n "$requested_host" ]]; then
              printf 'dotfiles-lan-hosts: only one HOST may be specified\n' >&2
              exit 2
            fi
            requested_host="$1"
            shift
            ;;
        esac
      done

      safe_ssh_options=(
        ${safeSshOptions discoveryKnownHosts}
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

      prefix_allowed() {
        local prefix="$1"
        local trusted

        if [[ "$allow_untrusted" == 1 ]]; then
          return 0
        fi

        for trusted in $trusted_subnets; do
          if [[ "$prefix" == "$trusted" ]]; then
            return 0
          fi
        done
        return 1
      }

      active_prefixes() {
        local_ipv4_addresses | while IFS=. read -r a b c _; do
          if [[ -n "''${a:-}" && -n "''${b:-}" && -n "''${c:-}" ]]; then
            printf '%s.%s.%s\n' "$a" "$b" "$c"
          fi
        done | sort -u
      }

      network_is_trusted() {
        local prefix

        while read -r prefix; do
          if prefix_allowed "$prefix"; then
            return 0
          fi
        done < <(active_prefixes)
        return 1
      }

      if ! network_is_trusted; then
        printf '%s\n' 'dotfiles-lan-hosts: refusing to scan outside a trusted LAN' >&2
        printf 'Active /24 prefixes: %s\n' "$(active_prefixes | tr '\n' ' ')" >&2
        printf 'Trusted /24 prefixes: %s\n' "$trusted_subnets" >&2
        printf '%s\n' 'Set DOTFILES_LAN_TRUSTED_SUBNETS or explicitly use DOTFILES_LAN_ALLOW_UNTRUSTED=1.' >&2
        exit 1
      fi

      local_prefixes() {
        {
          for prefix in ''${DOTFILES_LAN_SUBNETS:-}; do
            if prefix_allowed "$prefix"; then
              printf '%s\n' "$prefix"
            fi
          done

          active_prefixes | while read -r prefix; do
            if prefix_allowed "$prefix"; then
              printf '%s\n' "$prefix"
            fi
          done

          # Current home LAN hint. Keep this as a fallback only; dynamic discovery
          # above wins when the client is on another network.
          if prefix_allowed 192.168.4; then
            printf '192.168.4\n'
          fi
        } | sort -u
      }

      candidate_ips() {
        {
          for ip in ''${DOTFILES_LAN_IPS:-}; do
            IFS=. read -r a b c _ <<<"$ip"
            if [[ -n "''${a:-}" && -n "''${b:-}" && -n "''${c:-}" ]] && prefix_allowed "$a.$b.$c"; then
              printf '%s\n' "$ip"
            fi
          done

          # Recent/static hints first so common cases return quickly.
          if prefix_allowed 192.168.4; then
            printf '192.168.4.28\n'
          fi

          local_prefixes | while read -r prefix; do
            for suffix in $(seq 1 254); do
              printf '%s.%s\n' "$prefix" "$suffix"
            done
          done
        } | sort -u
      }

      network_identity() {
        local default_route=""
        local interface=""

        printf '%s\n' 'addresses:'
        local_ipv4_addresses | sort -u

        if command -v ip >/dev/null 2>&1; then
          default_route="$(ip -4 route show default 2>/dev/null | sort -u || true)"
        elif command -v route >/dev/null 2>&1 || [[ -x /sbin/route ]]; then
          default_route="$("$(command -v route || printf /sbin/route)" -n get default 2>/dev/null || true)"
        fi

        printf '%s\n' 'default-route:' "$default_route"

        if [[ "$default_route" =~ [[:space:]]dev[[:space:]]([^[:space:]]+) ]]; then
          interface="''${BASH_REMATCH[1]}"
        elif [[ "$default_route" =~ interface:[[:space:]]*([^[:space:]]+) ]]; then
          interface="''${BASH_REMATCH[1]}"
        fi

        if command -v networksetup >/dev/null 2>&1 || [[ -x /usr/sbin/networksetup ]]; then
          printf '%s\n' 'wifi-network:'
          "$(command -v networksetup || printf /usr/sbin/networksetup)" -getairportnetwork "''${interface:-en0}" 2>/dev/null || true
        elif command -v iwgetid >/dev/null 2>&1; then
          printf '%s\n' 'wifi-network:'
          iwgetid --raw 2>/dev/null || true
        elif command -v nmcli >/dev/null 2>&1; then
          printf '%s\n' 'network-connection:'
          nmcli -t -f GENERAL.CONNECTION device show "$interface" 2>/dev/null || true
        fi
      }

      cache_ttl="''${DOTFILES_LAN_CACHE_TTL:-3600}"
      if ! [[ "$cache_ttl" =~ ^[0-9]{1,7}$ ]]; then
        cache_ttl=3600
      else
        cache_ttl=$((10#$cache_ttl))
      fi

      cache_scope="$({
        printf 'user=%s\n' "$user"
        printf 'ips=%s\n' "''${DOTFILES_LAN_IPS:-}"
        printf 'host-keys=%s\n' ${lib.escapeShellArg (lib.concatStringsSep "|" (lib.mapAttrsToList (host: key: "${host}=${key}") cfg.hostKeys))}
        printf 'host-hints=%s\n' ${lib.escapeShellArg (lib.concatStringsSep "|" (lib.mapAttrsToList (host: ips: "${host}=${lib.concatStringsSep "," ips}") cfg.hostHints))}
        local_prefixes
        network_identity
      } | sha256sum | cut -d ' ' -f 1)"
      if [[ -n "$requested_host" ]]; then
        request_scope="$(printf '%s' "$requested_host" | sha256sum | cut -d ' ' -f 1)"
      else
        request_scope=all
      fi
      cache_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
      cache_file="$cache_dir/lan-hosts-$cache_scope-$request_scope.tsv"

      print_results() {
        local results="$1"

        if [[ -n "$requested_host" ]]; then
          results="$(results_for_request "$results")"
          if [[ -z "$results" ]]; then
            return 1
          fi
        fi

        if [[ "$print_ip_only" == true ]]; then
          printf '%s\n' "$results" | head -n 1 | while IFS=$'\t' read -r _ ip; do
            printf '%s\n' "$ip"
          done
        else
          printf '%s\n' "$results"
        fi
      }

      results_for_request() {
        local results="$1"

        printf '%s\n' "$results" | while IFS=$'\t' read -r host ip; do
          if [[ "$host" == "$requested_host" ]]; then
            printf '%s\t%s\n' "$host" "$ip"
          fi
        done
      }

      write_cache() {
        local results="$1"
        local cache_tmp

        mkdir -p "$cache_dir"
        cache_tmp="$(mktemp "$cache_dir/.lan-hosts.XXXXXX")"
        if [[ -n "$results" ]]; then
          printf '%s\n' "$results" >"$cache_tmp"
        else
          : >"$cache_tmp"
        fi
        mv "$cache_tmp" "$cache_file"
      }

      if [[ "$use_cache" == true && -f "$cache_file" ]]; then
        now="$(date +%s)"
        cache_mtime="$(stat -c %Y "$cache_file" 2>/dev/null || printf 0)"
        if [[ "$cache_mtime" =~ ^[0-9]+$ ]]; then
          cache_age=$((now - cache_mtime))
          if (( cache_age >= 0 && cache_age <= cache_ttl )); then
            cached_results="$(sort -u "$cache_file")"
            if [[ -n "$requested_host" && -z "$cached_results" ]]; then
              rm -f "$cache_file"
            elif print_results "$cached_results"; then
              exit 0
            else
              printf 'dotfiles-lan-hosts: no reachable host named %s\n' "$requested_host" >&2
              exit 1
            fi
          fi
        fi
      fi

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

      hint_ips() {
        for ip in ''${DOTFILES_LAN_IPS:-}; do
          printf '%s\n' "$ip"
        done

        case "$requested_host" in
          ${lib.concatMapStringsSep "\n" (host: ''
        ${lib.escapeShellArg host}) printf '%s\n' ${lib.concatMapStringsSep " " lib.escapeShellArg cfg.hostHints.${host}} ;;
      '') (builtins.attrNames cfg.hostHints)}
        esac
      }

      if [[ -n "$requested_host" ]]; then
        while read -r ip; do
          [[ -n "$ip" ]] || continue
          IFS=. read -r a b c _ <<<"$ip"
          if ! [[ -n "''${a:-}" && -n "''${b:-}" && -n "''${c:-}" ]] || ! prefix_allowed "$a.$b.$c"; then
            continue
          fi
          probe "$ip"
          results="$(cat "$tmpdir"/* 2>/dev/null | sort -u || true)"
          if print_results "$results" >/dev/null; then
            host_results="$(results_for_request "$results")"
            write_cache "$host_results"
            print_results "$host_results"
            exit 0
          fi
        done < <(hint_ips | sort -u)
      fi

      for ip in $(candidate_ips); do
        probe "$ip" &
        while [[ "$(jobs -pr | wc -l | tr -d ' ')" -ge "$max_jobs" ]]; do
          wait -n || true
        done
      done
      wait || true

      results="$(cat "$tmpdir"/* 2>/dev/null | sort -u || true)"

      if [[ -n "$requested_host" ]]; then
        host_results="$(results_for_request "$results")"
        if [[ -n "$host_results" ]]; then
          write_cache "$host_results"
        else
          rm -f "$cache_file"
        fi
      else
        write_cache "$results"
      fi

      if ! print_results "$results"; then
        printf 'dotfiles-lan-hosts: no reachable host named %s\n' "$requested_host" >&2
        exit 1
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
      the fleet host key configured for that name.
      EOF
        exit 0
      fi

      host="$1"
      shift
      user="''${DOTFILES_LAN_SSH_USER:-chris}"
      known_hosts_file=""

      case "$host" in
        ${lib.concatMapStringsSep "\n" (host: ''
        ${lib.escapeShellArg host}) known_hosts_file=${lib.escapeShellArg (toString hostKnownHosts.${host})} ;;
      '') (builtins.attrNames hostKnownHosts)}
        *)
          printf 'ssh-lan: no trusted host key configured for %s\n' "$host" >&2
          exit 1
          ;;
      esac

      ip="$(dotfiles-lan-hosts --ip "$host")"

      safe_ssh_options=(
        ${safeSshOptions ''"$known_hosts_file"''}
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
  options.dotfiles.shell.lanSsh = {
    enable = dotfiles_lib.options.mkDefaultEnabledOption "Install DHCP-friendly local-network SSH discovery and safe SSH helpers.";
    hostKeys = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = defaultHostKeys;
      description = "Trusted SSH host public keys keyed by the hostname returned during LAN discovery.";
    };
    hostHints = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = {
        thorny = ["192.168.4.28"];
      };
      description = "Likely LAN IPs to authenticate before falling back to a full subnet scan.";
    };
  };

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
