{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  skipFingerprintWhenLidClosed = pkgs.writeShellApplication {
    name = "skip-fingerprint-when-lid-closed";
    runtimeInputs = [pkgs.gnugrep];
    text = ''
      for lid_state in /proc/acpi/button/lid/*/state; do
        if [ -r "$lid_state" ] && grep -qi 'closed' "$lid_state"; then
          exit 0
        fi
      done

      exit 1
    '';
  };

  mkLidAwareFingerprintPam = serviceName: {
    fprintAuth = true;
    rules.auth.skip-fprintd-when-lid-closed = {
      # If the lid is closed, skip the next auth rule, which is the built-in
      # pam_fprintd rule. This avoids the greeter blocking on an inaccessible
      # fingerprint reader in docked clamshell mode while preserving fingerprint
      # login when the laptop is open.
      order = config.security.pam.services.${serviceName}.rules.auth.fprintd.order - 1;
      control = "[success=1 default=ignore]";
      modulePath = "${config.security.pam.package}/lib/security/pam_exec.so";
      args = [
        "quiet"
        "${lib.getExe skipFingerprintWhenLidClosed}"
      ];
    };
  };
in {
  imports = [
    inputs.nixos-modules.nixosModules.common
    inputs.nixos-modules.nixosModules.desktopCommon
    inputs.nixos-modules.nixosModules.networking
    inputs.nixos-modules.nixosModules.sound
    inputs.nixos-modules.nixosModules.tailscale
    inputs.nixos-modules.nixosModules.useRemoteBuilds
    inputs.nixos-modules.nixosModules.virtualization
    inputs.nixos-modules.nixosModules.users.chris
    inputs.nixos-modules.nixosModules.hyprlandDesktop
    ./hardware.nix
    inputs.agenix.nixosModules.default
    # ThinkPad T14s Gen 5 AMD hardware support
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-t14-amd-gen5
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate
    inputs.nixos-hardware.nixosModules.common-gpu-amd
    inputs.nixos-hardware.nixosModules.common-pc-laptop
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
  ];

  # Enable Hyprland desktop environment
  dotfiles.hyprland-desktop.enable = true;
  # Hyprspace is a Hyprland plugin and must be loaded by the exact Hyprland
  # build it was compiled against. Use the pinned tater Hyprland input for the
  # system session package as well as the Home Manager config below.
  programs.hyprland.package = inputs.hyprland.packages.${pkgs.system}.hyprland;
  xdg.portal.extraPortals = lib.mkForce [
    inputs.hyprland.packages.${pkgs.system}.xdg-desktop-portal-hyprland
    pkgs.xdg-desktop-portal-gtk
  ];

  # Agenix secrets
  age.secrets.openrouter-api-key = {
    file = ../../../secrets/openrouter-api-key.age;
    owner = "chris";
    group = "users";
    mode = "0400";
  };
  age.secrets.gpg-private-key = {
    file = ../../../secrets/gpg-private-key.age;
    owner = "chris";
    group = "users";
    mode = "0400";
  };
  age.secrets.gpg-key-id = {
    file = ../../../secrets/gpg-key-id.age;
    owner = "chris";
    group = "users";
    mode = "0400";
  };

  networking.hostName = "tater";

  # MT7925e stability mitigations. Keep these host-local: this card has been
  # prone to firmware/driver stalls on tater even after platform firmware
  # updates. Prefer newer kernel fixes, avoid Wi-Fi powersave from both
  # NetworkManager and TLP, and use iwd for Wi-Fi association.
  boot.kernelPackages = pkgs.linuxPackages_latest;
  networking.networkmanager = {
    wifi = {
      backend = "iwd";
      powersave = false;
    };
  };
  networking.wireless.iwd = {
    enable = true;
    settings = {
      General = {
        EnableNetworkConfiguration = false;
      };
      Settings = {
        AutoConnect = true;
      };
    };
  };
  hardware.wirelessRegulatoryDatabase = true;
  systemd.services.NetworkManager.serviceConfig = {
    Restart = "always";
    RestartSec = "3s";
  };

  # Fingerprint reader support
  services.fprintd.enable = true;
  services.fprintd.tod.enable = true;
  services.fprintd.tod.driver = pkgs.libfprint-2-tod1-goodix;
  security.pam.services.hyprlock = {
    fprintAuth = false;
    unixAuth = true;
  };
  security.pam.services.greetd = mkLidAwareFingerprintPam "greetd";
  security.pam.services.regreet = mkLidAwareFingerprintPam "regreet";
  # In clamshell mode the fingerprint reader is physically unavailable, and
  # sudo's PAM stack waits for fingerprint auth before accepting a password.
  # Keep fingerprints for login/unlock paths but make terminal elevation prompt
  # for the password immediately.
  security.pam.services.sudo.fprintAuth = false;

  # Firmware updates
  services.fwupd.enable = true;

  # Keep the laptop timezone in sync with the current location when traveling.
  # The desktop-common Los Angeles timezone is only the offline/default value;
  # automatic-timezoned updates it through geoclue + systemd-timedated once the
  # laptop has network/location data after landing somewhere else.
  services.automatic-timezoned.enable = true;

  # Power management for ThinkPad
  services.logind.settings.Login = {
    # Let Hyprland handle lid-close locking/display changes. When docked with an
    # external monitor, keep the machine awake for clamshell mode.
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };
  systemd.sleep.settings.Sleep = {
    AllowHibernation = "yes";
    AllowSuspendThenHibernate = "yes";
    HibernateDelaySec = "1h";
  };

  services.tlp = {
    enable = true;
    settings = {
      # Keep AC performance responsive without pinning the CPU in the most
      # aggressive profile. The previous performance/performance pairing caused
      # frequent fan ramp-ups during bursty desktop workloads on the T14s.
      CPU_SCALING_GOVERNOR_ON_AC = "schedutil";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_AC = "balance_performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      PLATFORM_PROFILE_ON_AC = "balanced";
      PLATFORM_PROFILE_ON_BAT = "low-power";
      CPU_BOOST_ON_BAT = 0;
      START_CHARGE_THRESH_BAT0 = 75;
      STOP_CHARGE_THRESH_BAT0 = 80;
      WIFI_PWR_ON_AC = "off";
      # MT7925e on Linux still appears to have intermittent disconnect/recovery
      # issues on some kernel + linux-firmware combinations, especially around
      # power saving / roaming / higher-band behavior. Keep Wi-Fi powersave off
      # on battery as a mitigation until this host remains stable across newer
      # nixpkgs/linux-firmware updates and firmware updates, at which point we
      # can retest and consider removing this override.
      WIFI_PWR_ON_BAT = "off";
    };
  };

  # Thermal management
  services.thermald.enable = true;

  # LUKS configuration is handled by disko (see disk-config.nix)

  hardware.graphics.enable = true;
  # The shared nixos-hardware AMD GPU profile enables 32-bit Mesa for broader
  # gaming/Wine compatibility. Tater does not use those workloads, so keep only
  # the native graphics stack to avoid a duplicate Mesa/LLVM closure.
  hardware.graphics.enable32Bit = lib.mkForce false;
  hardware.enableRedistributableFirmware = true;

  # Bluetooth support
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  system.stateVersion = "26.05";

  # Podman for rootless containers
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  users.users.chris.extraGroups = ["libvirtd" "podman"];

  home-manager.users.chris = {
    config,
    lib,
    ...
  }: let
    # GUI services that require a display and will hang during activation
    # These get RefuseManualStart=yes so sd-switch skips them, but they still
    # start normally via graphical-session.target when you log in
    guiServicesToSkip = [
      "blueman-applet"
      "hyprpaper"
      "hypridle"
      "swaync"
      "network-manager-applet"
      "udiskie"
      "mako"
      "gammastep"
      "com.mitchellh.ghostty"
      "mega-cmd-server-init"
    ];
    mkSkipDuringActivation = name:
      lib.nameValuePair name {
        Unit = {
          # Skip this service during home-manager activation (sd-switch respects this)
          # The service will still start normally via WantedBy when graphical session starts
          RefuseManualStart = lib.mkForce true;
        };
      };
    taterNetworkRecover = pkgs.writeShellApplication {
      name = "tater-network-recover";
      runtimeInputs = [pkgs.networkmanager pkgs.kmod pkgs.systemd pkgs.ripgrep];
      text = ''
        set -euo pipefail

        iface="''${1:-wlp194s0}"

        echo "== NetworkManager status =="
        nmcli general status || true
        nmcli device status || true

        echo "== Recent relevant logs =="
        journalctl -b --no-pager -n 120 \
          | rg -i "mt7925|mt76|''${iface}|NetworkManager|firmware|timeout|reset|failed" || true

        echo "== Bounce NetworkManager networking =="
        nmcli networking off || true
        sleep 3
        nmcli networking on || true
        sleep 5

        if nmcli -t -f DEVICE,STATE device status | rg -q "^''${iface}:connected$"; then
          echo "''${iface} is connected after NetworkManager bounce."
          exit 0
        fi

        echo "== Reconnect Wi-Fi device =="
        nmcli device disconnect "''${iface}" || true
        sleep 3
        nmcli device connect "''${iface}" || true
        sleep 5

        if nmcli -t -f DEVICE,STATE device status | rg -q "^''${iface}:connected$"; then
          echo "''${iface} is connected after device reconnect."
          exit 0
        fi

        echo "== Restart NetworkManager =="
        sudo systemctl restart NetworkManager.service
        sleep 5

        if nmcli -t -f DEVICE,STATE device status | rg -q "^''${iface}:connected$"; then
          echo "''${iface} is connected after NetworkManager restart."
          exit 0
        fi

        echo "== Reload mt7925e driver stack =="
        sudo modprobe -r mt7925e mt792x_lib mt76_connac_lib mt76 || true
        sleep 3
        sudo modprobe mt7925e
        sleep 5
        nmcli device wifi rescan || true
        nmcli device status || true
      '';
    };
    taterDisplayRefresh = pkgs.writeShellApplication {
      name = "tater-display-refresh";
      runtimeInputs = [pkgs.coreutils config.programs.eww.package pkgs.hyprland pkgs.jq];
      text = ''
        set -euo pipefail

        monitors_json() {
          hyprctl monitors -j 2>/dev/null || printf '[]\n'
        }

        has_enabled_monitor() {
          local name="$1"
          monitors_json | jq -e --arg name "$name" '.[] | select(.name == $name and (((.disabled // false) | not)))' >/dev/null
        }

        enabled_external_count() {
          monitors_json | jq '[.[] | select(.name != "eDP-1" and (((.disabled // false) | not)))] | length'
        }

        enabled_external_monitor() {
          monitors_json | jq -r 'first(.[] | select(.name != "eDP-1" and (((.disabled // false) | not))) | .name) // empty'
        }

        external_bar_for_monitor() {
          case "$1" in
            DP-1) printf '%s\n' bar-external-dp1 ;;
            DP-2) printf '%s\n' bar-external ;;
            DP-3) printf '%s\n' bar-external-dp3 ;;
            HDMI-A-1) printf '%s\n' bar-external-hdmi-a-1 ;;
            HDMI-A-2) printf '%s\n' bar-external-hdmi-a-2 ;;
            *) return 1 ;;
          esac
        }

        close_external_bars() {
          local keep="''${1:-}"
          for bar in bar-external-dp1 bar-external bar-external-dp3 bar-external-hdmi-a-1 bar-external-hdmi-a-2; do
            [[ "$bar" == "$keep" ]] && continue
            eww close "$bar" || true
          done
        }

        orient_workspaces() {
          local external_monitor="$1"

          move_clients_from_workspace() {
            local from="$1"
            local to="$2"

            hyprctl clients -j \
              | jq -r --argjson from "$from" '.[] | select(.workspace.id == $from) | .address' \
              | while read -r address; do
                [[ -z "$address" ]] && continue
                hyprctl dispatch movetoworkspacesilent "$to,address:$address" >/dev/null 2>&1 || true
              done
          }

          if ! has_enabled_monitor eDP-1; then
            # In clamshell/external-only mode, remap the laptop-oriented
            # workspace range onto the external-oriented range so windows do not
            # stay stranded on 6-10 after docking from an undocked session.
            move_clients_from_workspace 6 1
            move_clients_from_workspace 7 2
            move_clients_from_workspace 8 3
            move_clients_from_workspace 9 4
            move_clients_from_workspace 10 5
          fi

          active_external_workspace="$(monitors_json | jq -r --arg monitor "$external_monitor" '.[] | select(.name == $monitor) | .activeWorkspace.id // empty')"
          if [[ -n "$active_external_workspace" && "$active_external_workspace" -gt 10 ]]; then
            move_clients_from_workspace "$active_external_workspace" 1
          fi

          for workspace in 1 2 3 4 5; do
            hyprctl dispatch moveworkspacetomonitor "$workspace" "$external_monitor" >/dev/null 2>&1 || true
          done

          if has_enabled_monitor eDP-1; then
            for workspace in 6 7 8 9 10; do
              hyprctl dispatch moveworkspacetomonitor "$workspace" eDP-1 >/dev/null 2>&1 || true
            done
          fi

          # When docking from an undocked session, Hyprland can leave focus on a
          # higher-numbered transient workspace on the new external output. Move
          # the external monitor back to the expected primary workspace range so
          # the bar and keyboard shortcuts start from a predictable orientation.
          if [[ -z "$active_external_workspace" || "$active_external_workspace" -lt 1 || "$active_external_workspace" -gt 5 ]]; then
            hyprctl dispatch focusmonitor "$external_monitor" >/dev/null 2>&1 || true
            hyprctl dispatch workspace 1 >/dev/null 2>&1 || true
          fi
        }

        # If tater was unplugged while the home clamshell profile had eDP-1
        # disabled, Hyprland can briefly have no enabled output for Eww to bind
        # to.  Make the laptop panel the fail-safe whenever no external monitor
        # is currently enabled; kanshi still owns the normal steady-state layout.
        if [[ "$(enabled_external_count)" -eq 0 ]]; then
          hyprctl keyword monitor "eDP-1,1920x1200@60,0x0,1.5" || true
          hyprctl dispatch dpms on || true
        fi

        for _ in 1 2 3 4 5; do
          if has_enabled_monitor DP-2 || has_enabled_monitor eDP-1; then
            break
          fi
          sleep 0.2
        done

        eww daemon || true
        sleep 0.2

        external_monitor="$(enabled_external_monitor)"
        if [[ -n "$external_monitor" ]] && external_bar="$(external_bar_for_monitor "$external_monitor")"; then
          orient_workspaces "$external_monitor"
          eww open "$external_bar" || true
          eww close bar-internal || true
          close_external_bars "$external_bar"
        elif has_enabled_monitor eDP-1; then
          eww open bar-internal || true
          close_external_bars
        else
          eww close bar-internal || true
          close_external_bars
        fi
      '';
    };
    taterHomeClamshell = pkgs.writeShellApplication {
      name = "tater-home-clamshell";
      runtimeInputs = [pkgs.hyprland taterDisplayRefresh];
      text = ''
        set -euo pipefail

        hyprctl keyword monitor "DP-2,3840x2160@60,0x0,1"
        hyprctl keyword monitor "eDP-1,disable"
        tater-display-refresh
      '';
    };
    taterHomeOpen = pkgs.writeShellApplication {
      name = "tater-home-open";
      runtimeInputs = [pkgs.hyprland taterDisplayRefresh];
      text = ''
        set -euo pipefail

        hyprctl keyword monitor "eDP-1,1920x1200@60,0x640,1.5"
        hyprctl keyword monitor "DP-2,3840x2160@60,1280x0,1"
        tater-display-refresh
      '';
    };
    taterHomeToggle = pkgs.writeShellApplication {
      name = "tater-home-toggle";
      runtimeInputs = [pkgs.hyprland pkgs.jq pkgs.libnotify taterDisplayRefresh];
      text = ''
        set -euo pipefail

        refresh_bars() {
          tater-display-refresh
        }

        if hyprctl monitors -j | jq -e '.[] | select(.name == "DP-2" and .model == "DELL U4320Q" and (((.disabled // false) | not)))' >/dev/null; then
          if hyprctl monitors -j | jq -e '.[] | select(.name == "eDP-1" and (((.disabled // false) | not)))' >/dev/null; then
            hyprctl keyword monitor "DP-2,3840x2160@60,0x0,1"
            hyprctl keyword monitor "eDP-1,disable"
            refresh_bars
            notify-send "Home display" "Laptop panel off; using Dell only" || true
          else
            hyprctl keyword monitor "eDP-1,1920x1200@60,0x640,1.5"
            hyprctl keyword monitor "DP-2,3840x2160@60,1280x0,1"
            refresh_bars
            notify-send "Home display" "Laptop panel on with Dell" || true
          fi
        else
          notify-send "Home display" "Dell U4320Q is not connected on DP-2" || true
          exit 1
        fi
      '';
    };
    taterHomeDocked = pkgs.writeShellApplication {
      name = "tater-home-docked";
      runtimeInputs = [pkgs.hyprland pkgs.jq];
      text = ''
        set -euo pipefail

        monitors=$(hyprctl monitors -j)

        # Home clamshell mode means the known desk monitor is active and the
        # laptop panel is not enabled. Keep open-lid docked use on the normal
        # laptop idle policy so travel/temporary-desk behavior stays conservative.
        if ! jq -e '.[] | select(.name == "DP-2" and (.model == "DELL U4320Q" or .model == "DELL U4323QE" or .model == "DELL P4317Q"))' <<<"$monitors" >/dev/null; then
          exit 1
        fi

        if jq -e '.[] | select(.name == "eDP-1" and (((.disabled // false) | not)))' <<<"$monitors" >/dev/null; then
          exit 1
        fi
      '';
    };
    taterDimScreen = pkgs.writeShellApplication {
      name = "tater-dim-screen";
      runtimeInputs = [pkgs.brightnessctl pkgs.coreutils];
      text = ''
        current=$(brightnessctl g)
        max=$(brightnessctl m)

        if [ -z "$current" ] || [ -z "$max" ] || [ "$max" -le 0 ]; then
          exit 0
        fi

        # Dim relative to current brightness (about 30%), never increase.
        target=$((current / 3))
        if [ "$target" -lt 1 ]; then
          target=1
        fi

        brightnessctl -s set "$target"
      '';
    };
    taterDesktopDoctor = pkgs.writeShellApplication {
      name = "tater-desktop-doctor";
      runtimeInputs = [pkgs.coreutils config.programs.eww.package pkgs.hyprland pkgs.jq pkgs.kmod pkgs.networkmanager pkgs.ripgrep pkgs.systemd];
      text = ''
        set -uo pipefail

        failures=0
        warnings=0

        pass() { printf 'PASS  %s\n' "$*"; }
        warn() { printf 'WARN  %s\n' "$*"; warnings=$((warnings + 1)); }
        fail() { printf 'FAIL  %s\n' "$*"; failures=$((failures + 1)); }
        have() { command -v "$1" >/dev/null 2>&1; }
        active() { systemctl "$1" is-active --quiet "$2"; }

        echo "== Session =="
        if [[ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && hyprctl monitors -j >/tmp/tater-doctor-monitors.json 2>/dev/null; then
          pass "Hyprland IPC is available"
        else
          fail "Hyprland IPC is not available; run this inside the Hyprland session"
          printf '\nSummary: %d failure(s), %d warning(s)\n' "$failures" "$warnings"
          exit 1
        fi

        if active --user hypridle.service; then pass "hypridle user service is active"; else warn "hypridle user service is not active"; fi
        if active --user kanshi.service; then pass "kanshi user service is active"; else warn "kanshi user service is not active"; fi

        echo
        echo "== Login and auth plumbing =="
        if active --system greetd.service; then pass "greetd system service is active"; else fail "greetd system service is not active"; fi
        if rg -q '^Hyprland$' /etc/greetd/environments 2>/dev/null; then pass "Hyprland is listed in greetd environments"; else fail "Hyprland is missing from /etc/greetd/environments"; fi
        if active --system fprintd.service; then pass "fprintd system service is active"; else warn "fprintd system service is not active yet; it may be socket/dbus activated"; fi

        echo
        echo "== Network and Wi-Fi stability =="
        if active --system NetworkManager.service; then pass "NetworkManager is active"; else fail "NetworkManager is not active"; fi
        if active --system iwd.service; then pass "iwd is active for NetworkManager Wi-Fi backend"; else warn "iwd is not active"; fi
        if nmcli -t -f DEVICE,TYPE,STATE device status | rg -q '^[^:]+:wifi:connected$'; then
          pass "Wi-Fi is connected"
        else
          warn "No connected Wi-Fi device found"
        fi
        if lsmod | rg -q '^mt7925e\b'; then pass "mt7925e driver is loaded"; else warn "mt7925e driver is not currently loaded"; fi

        echo
        echo "== Displays =="
        if jq -e '.[] | select(.name == "eDP-1" and (((.disabled // false) | not)))' /tmp/tater-doctor-monitors.json >/dev/null; then
          pass "Internal panel eDP-1 is present/enabled"
        else
          warn "Internal panel eDP-1 is not present/enabled; expected in clamshell mode"
        fi
        if jq -e '.[] | select(.name == "DP-2" and .model == "DELL U4320Q" and .serial == "1LTJW13" and (((.disabled // false) | not)))' /tmp/tater-doctor-monitors.json >/dev/null; then
          pass "Home Dell U4320Q is detected on DP-2"
          if jq -e '.[] | select(.name == "DP-2" and .width == 3840 and .height == 2160 and .scale == 1)' /tmp/tater-doctor-monitors.json >/dev/null; then
            pass "Home Dell is using 3840x2160 scale 1"
          else
            fail "Home Dell is not at expected 3840x2160 scale 1"
          fi
        else
          warn "Home Dell U4320Q is not detected on DP-2"
        fi

        echo
        echo "== Workspaces =="
        if hyprctl workspaces -j >/tmp/tater-doctor-workspaces.json 2>/dev/null; then
          for ws in 1 2 3 4 5; do
            if jq -e --argjson ws "$ws" '.[] | select(.id == $ws and .monitor == "DP-2")' /tmp/tater-doctor-workspaces.json >/dev/null; then
              pass "Workspace $ws is on DP-2"
            else
              warn "Workspace $ws is not currently on DP-2; it may not exist until visited"
            fi
          done
          if jq -e '.[] | select(.name == "eDP-1" and (((.disabled // false) | not)))' /tmp/tater-doctor-monitors.json >/dev/null; then
            for ws in 6 7 8 9 10; do
              if jq -e --argjson ws "$ws" '.[] | select(.id == $ws and .monitor == "eDP-1")' /tmp/tater-doctor-workspaces.json >/dev/null; then
                pass "Workspace $ws is on eDP-1"
              else
                warn "Workspace $ws is not currently on eDP-1; it may not exist until visited"
              fi
            done
          fi
        else
          fail "Could not query Hyprland workspaces"
        fi

        echo
        echo "== Eww bars =="
        if have eww && eww active-windows >/tmp/tater-doctor-eww.txt 2>/dev/null; then
          if jq -e '.[] | select(.name == "DP-2" and (((.disabled // false) | not)))' /tmp/tater-doctor-monitors.json >/dev/null; then
            if rg -q 'bar-external' /tmp/tater-doctor-eww.txt; then pass "External Eww bar is open"; else fail "External Eww bar is not open while DP-2 is enabled"; fi
            if rg -q 'bar-internal' /tmp/tater-doctor-eww.txt; then fail "Internal Eww bar is also open while DP-2 is active"; else pass "Internal Eww bar is closed while DP-2 is active"; fi
          elif jq -e '.[] | select(.name == "eDP-1" and (((.disabled // false) | not)))' /tmp/tater-doctor-monitors.json >/dev/null; then
            if rg -q 'bar-internal' /tmp/tater-doctor-eww.txt; then pass "Internal Eww bar is open"; else fail "Internal Eww bar is not open while eDP-1 is enabled"; fi
            if rg -q 'bar-external' /tmp/tater-doctor-eww.txt; then fail "External Eww bar is open without DP-2"; else pass "External Eww bar is closed without DP-2"; fi
          fi
        else
          warn "Could not query Eww active windows"
        fi

        echo
        printf 'Summary: %d failure(s), %d warning(s)\n' "$failures" "$warnings"
        if [[ "$failures" -gt 0 ]]; then exit 1; fi
      '';
    };
    thornyStatus = pkgs.writeShellApplication {
      name = "thorny-status-remote";
      runtimeInputs = [pkgs.openssh];
      text = ''
        set -euo pipefail

        host="''${1:-thorny}"
        shift || true

        exec ssh -t "$host" thorny-status "$@"
      '';
    };
  in {
    # secrets are passed via _module.args in nixos-modules/modules/users/chris.nix
    home.stateVersion = "26.05";
    imports = [
      inputs.hm-modules.homeManagerModules.default
      # Fix for ghostty validation to prevent activation timeouts
      inputs.hm-modules.homeManagerModules.ghostty-fix
    ];

    # Keep service restarts enabled, but skip GUI services that hang without a display
    systemd.user.startServices = true;
    systemd.user.services = lib.listToAttrs (map mkSkipDuringActivation guiServicesToSkip);

    # Use the unified Hyprland workstation configuration
    dotfiles.hyprland-workstation.enable = true;
    dotfiles.hyprland-workstation.terminal = "ghostty";

    programs.hyprlock.settings.auth.fingerprint.enabled = true;

    # Prefer Hypridle + Hyprlock (disable swayidle/swaylock)
    dotfiles.gui.swayidle.enable = false;
    dotfiles.hypridle.timeouts = {
      dim = 120;
      lock = 300;
      dpms = 360;
      suspend = 420;
      hibernate = 1200;
    };
    services.hypridle.settings.listener = let
      homeDocked = lib.getExe taterHomeDocked;
      dimScreen = lib.getExe taterDimScreen;
      idleInhibit = "dotfiles-idle-inhibit";
    in
      lib.mkForce [
        {
          # Dim screen: same behavior in every posture.
          timeout = 120;
          on-timeout = "if ! ${idleInhibit} active; then ${dimScreen}; fi";
          on-resume = "${pkgs.brightnessctl}/bin/brightnessctl -r";
        }
        {
          # Laptop/travel lock policy. Home clamshell gets a longer timer below.
          timeout = 300;
          on-timeout = "if ! ${idleInhibit} active && ! ${homeDocked}; then loginctl lock-session; fi";
        }
        {
          # Laptop/travel display-off policy. In home clamshell, keep the desk
          # display awake until just after the 10-minute lock.
          timeout = 360;
          on-timeout = "if ! ${idleInhibit} active && ! ${homeDocked}; then hyprctl dispatch dpms off; fi";
          on-resume = "hyprctl dispatch dpms on";
        }
        {
          # Laptop/travel suspend policy.
          timeout = 420;
          on-timeout = "if ! ${idleInhibit} active && ! ${homeDocked}; then systemctl suspend-then-hibernate; fi";
        }
        {
          # Laptop/travel hibernate policy.
          timeout = 1200;
          on-timeout = "if ! ${idleInhibit} active && ! ${homeDocked}; then systemctl hibernate; fi";
        }
        {
          # Home clamshell lock policy.
          timeout = 600;
          on-timeout = "if ! ${idleInhibit} active && ${homeDocked}; then loginctl lock-session; fi";
        }
        {
          # Home clamshell display-off policy.
          timeout = 660;
          on-timeout = "if ! ${idleInhibit} active && ${homeDocked}; then hyprctl dispatch dpms off; fi";
          on-resume = "hyprctl dispatch dpms on";
        }
        {
          # Home clamshell suspend policy.
          timeout = 3600;
          on-timeout = "if ! ${idleInhibit} active && ${homeDocked}; then systemctl suspend-then-hibernate; fi";
        }
      ];

    # Keep Waybar disabled while Eww owns the primary bar and native systray.
    dotfiles.gui.hyprland.waybar.enable = false;
    dotfiles.gui.hyprland.waybar.trayOnly.enable = false;
    wayland.windowManager.hyprland.package = inputs.hyprland.packages.${pkgs.system}.hyprland;
    dotfiles.gui.hyprland.overview = {
      # Keep Hyprspace disabled for now. A missing overview dispatcher after
      # reboot means the compositor started without the plugin, and the pinned
      # plugin path has proven unstable enough to push Hyprland into safe mode.
      # Super+O still opens the script-backed overview/move menu from the shared
      # Hyprland module.
      enable = false;
      package = null;
    };

    # Docking polish: kanshi keeps monitor layouts deterministic as USB-C/HDMI
    # displays appear and disappear. The Dell 43" profiles are the preferred
    # home clamshell mode: close the lid, disable eDP-1, and use only the big
    # external display. The final wildcard profile remains a sane fallback for
    # unknown monitors when the lid is open.
    services.kanshi = {
      enable = true;
      settings = let
        mkDell43HomeProfile = criteria: {
          profile.name = "home-dell-43-${builtins.replaceStrings [" " "." "*"] ["-" "" "any"] criteria}";
          profile.exec = [
            (lib.getExe taterDisplayRefresh)
          ];
          profile.outputs = [
            {
              criteria = "eDP-1";
              status = "disable";
            }
            {
              inherit criteria;
              status = "enable";
              mode = "3840x2160@60Hz";
              position = "0,0";
              scale = 1.0;
            }
          ];
        };
      in [
        {
          profile.name = "undocked";
          profile.exec = [
            (lib.getExe taterDisplayRefresh)
          ];
          profile.outputs = [
            {
              criteria = "eDP-1";
              status = "enable";
              mode = "1920x1200@60Hz";
              position = "0,0";
              scale = 1.5;
            }
          ];
        }
        # Home Dell 43". The first entry is the exact monitor currently on the
        # desk; the wildcard U4320Q entry catches the same model via another
        # dock/cable if the serial ever reports differently.
        (mkDell43HomeProfile "Dell Inc. DELL U4320Q 1LTJW13")
        (mkDell43HomeProfile "Dell Inc. DELL U4323QE *")
        (mkDell43HomeProfile "Dell Inc. DELL U4320Q *")
        (mkDell43HomeProfile "Dell Inc. DELL P4317Q *")
        {
          profile.name = "docked-wildcard";
          profile.exec = [
            (lib.getExe taterDisplayRefresh)
          ];
          profile.outputs = [
            {
              criteria = "eDP-1";
              status = "enable";
              mode = "1920x1200@60Hz";
              position = "0,720";
              scale = 1.5;
            }
            {
              criteria = "*";
              status = "enable";
              position = "1440,0";
              scale = 1.0;
            }
          ];
        }
      ];
    };

    # Additional tools
    dotfiles.shell.yazi.enable = true;
    programs.opencode.enable = true;
    dotfiles.opencode.openrouterApiKeyFile = "/run/agenix/openrouter-api-key";
    programs.meganz.enable = true;
    programs.helium.enable = true;

    # GPG configuration with automatic key import
    dotfiles.gpg.enable = true;

    # Bluetooth and network management
    home.packages = [pkgs.overskride taterNetworkRecover taterDisplayRefresh taterHomeClamshell taterHomeOpen taterHomeToggle taterHomeDocked taterDesktopDoctor thornyStatus];
    services.network-manager-applet.enable = true;
  };
}
